defmodule Portfolio.Photography.Adapters.CachingAlbumCatalogAdapter do
  @moduledoc """
  Decorateur de cache et echelle de degradation devant un autre adaptateur de
  catalogue.

  Il implemente le meme port que l'adaptateur qu'il enveloppe : la couche web
  ne sait pas qu'il existe. Sa seule promesse tient en une phrase : le
  visiteur ne voit jamais de page vide et jamais d'erreur, meme plateforme
  eteinte.

  ## Les quatre paliers

  1. **Cache frais** (moins de `:fresh_for_ms`, dix minutes par defaut) :
     reponse immediate, aucun appel reseau.
  2. **Cache perime** : le contenu perime part immediatement, et un
     rafraichissement est lance hors du chemin de la requete, un seul en vol
     par cle. C'est le `stale-while-revalidate` du cache HTTP, applique ici.
  3. **Cache vide et plateforme muette** : relecture de l'instantane sur
     disque. C'est le palier du redemarrage de l'hote, ou les deux
     applications repartent ensemble et ou le portfolio, plus leger, est pret
     avant la plateforme.
  4. **Rien du tout** : `{:error, :unavailable}`. La couche web affiche alors
     sa navigation statique et le dit explicitement au visiteur, en 200.

  ## Ce qui n'est jamais mis en cache

  Les erreurs. Un echec ne remplace pas une entree valide : il la laisse
  vieillir. Un `:not_found` n'est pas mis en cache non plus, sinon la
  publication d'un album resterait invisible jusqu'a expiration.

  ## Instantane

  Seules la liste d'albums et la liste des themes sont conservees sur disque :
  ce sont les deux pages dont le vide serait inacceptable. Une fiche d'album
  indisponible retombe sur la liste, ce qui est acceptable.

  ## Memoire

  Le cache vit dans son propre espace Cachex (`:catalog_cache`), plafonne a
  cent entrees. L'ordre de grandeur mesure est d'environ 1,3 kilo-octet par
  photo decodee, voir `test/portfolio/photography/adapters/catalog_memory_test.exs`
  qui garde ce chiffre.

  ## Invalidation

  `invalidate_all/0` vide le cache et les instantanes. C'est ce que la
  procedure de retrait de consentement doit appeler : sans elle, un album
  depublie resterait visible jusqu'au prochain rafraichissement.
  """

  @behaviour Portfolio.Photography.Ports.AlbumCatalogPort

  require Logger

  alias Portfolio.Photography.Catalog.Decoder
  alias Portfolio.Photography.Catalog.Snapshot

  @cache :catalog_cache
  @default_fresh_for_ms :timer.minutes(10)
  @refresh_lock_ms :timer.seconds(30)

  @impl true
  def list_albums(opts \\ []) do
    key = {:albums, normalize_list_opts(opts)}

    read(key,
      fetch: fn -> inner().list_albums(opts) end,
      to_payload: &album_page_payload/1,
      from_payload: &Decoder.decode_album_list/1
    )
  end

  @impl true
  def get_album(slug, opts \\ []) when is_binary(slug) do
    key = {:album, slug, locale(opts)}

    read(key, fetch: fn -> inner().get_album(slug, opts) end)
  end

  @impl true
  def list_themes(opts \\ []) do
    key = {:themes, locale(opts)}

    read(key,
      fetch: fn -> inner().list_themes(opts) end,
      to_payload: &%{"data" => &1},
      from_payload: &Decoder.decode_theme_list/1
    )
  end

  @doc """
  Vide le cache memoire et les instantanes sur disque.

  A appeler lors d'un retrait de consentement ou de toute depublication qui
  ne peut pas attendre le prochain rafraichissement.
  """
  @spec invalidate_all() :: :ok
  def invalidate_all do
    _ = Cachex.clear(@cache)

    case snapshot_dir() do
      nil -> :ok
      dir -> _ = File.rm_rf(dir)
    end

    :ok
  end

  # ============================================================================
  # Echelle de degradation
  # ============================================================================

  defp read(key, opts) do
    case cached(key) do
      {:hit, value, age_ms} ->
        # Comparaison stricte : une fenetre de fraicheur a zero milliseconde
        # signifie « revalide a chaque lecture », ce qui est une configuration
        # legitime et pas un cas degenere.
        if age_ms < fresh_for_ms() do
          {:ok, value}
        else
          schedule_refresh(key, opts)
          {:ok, value}
        end

      :miss ->
        fetch_now(key, opts)
    end
  end

  defp fetch_now(key, opts) do
    case Keyword.fetch!(opts, :fetch).() do
      {:ok, value} ->
        store(key, value, fresh?: true)
        write_snapshot(key, value, opts)
        {:ok, value}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :unavailable} ->
        from_snapshot(key, opts)
    end
  end

  defp from_snapshot(key, opts) do
    with {:ok, from_payload} <- Keyword.fetch(opts, :from_payload),
         {:ok, payload} <- Snapshot.read(snapshot_dir(), key),
         {:ok, value} <- from_payload.(payload) do
      # L'instantane est par nature perime : on le stocke comme tel, pour que
      # la requete suivante declenche un rafraichissement en tache de fond.
      store(key, value, fresh?: false)
      {:ok, value}
    else
      _autre -> {:error, :unavailable}
    end
  end

  defp schedule_refresh(key, opts) do
    Task.Supervisor.start_child(Portfolio.TaskSupervisor, fn ->
      Cachex.fetch(
        @cache,
        {:refreshing, key},
        fn ->
          refresh(key, opts)
          {:commit, :en_cours, expire: @refresh_lock_ms}
        end
      )
    end)

    :ok
  end

  defp refresh(key, opts) do
    resultat =
      case Keyword.fetch!(opts, :fetch).() do
        {:ok, value} ->
          store(key, value, fresh?: true)
          write_snapshot(key, value, opts)
          :ok

        {:error, reason} ->
          # L'entree perimee reste en place : un echec ne remplace jamais une
          # valeur valide.
          reason
      end

    :telemetry.execute([:portfolio, :catalog, :refresh], %{count: 1}, %{
      key: key,
      outcome: resultat
    })
  end

  # ============================================================================
  # Cache
  # ============================================================================

  defp cached(key) do
    case Cachex.get(@cache, key) do
      {:ok, %{value: value, stored_at: stored_at}} ->
        {:hit, value, System.monotonic_time(:millisecond) - stored_at}

      _autre ->
        :miss
    end
  end

  defp store(key, value, fresh?: true) do
    Cachex.put(@cache, key, %{value: value, stored_at: System.monotonic_time(:millisecond)})
  end

  defp store(key, value, fresh?: false) do
    perime = System.monotonic_time(:millisecond) - fresh_for_ms() - 1
    Cachex.put(@cache, key, %{value: value, stored_at: perime})
  end

  # ============================================================================
  # Instantane
  # ============================================================================

  defp write_snapshot(key, value, opts) do
    case Keyword.get(opts, :to_payload) do
      nil -> :ok
      to_payload -> Snapshot.write(snapshot_dir(), key, to_payload.(value))
    end
  end

  defp album_page_payload(%{albums: albums, meta: meta}) do
    %{"data" => albums, "meta" => meta}
  end

  # ============================================================================
  # Configuration
  # ============================================================================

  defp normalize_list_opts(opts) do
    {Keyword.get(opts, :theme), locale(opts), Keyword.get(opts, :limit),
     Keyword.get(opts, :offset)}
  end

  defp locale(opts), do: Keyword.get(opts, :locale)

  defp inner do
    config(:inner_adapter, Portfolio.Photography.Adapters.HttpAlbumCatalogAdapter)
  end

  defp fresh_for_ms, do: config(:fresh_for_ms, @default_fresh_for_ms)

  defp snapshot_dir, do: config(:snapshot_dir, nil)

  defp config(key, default) do
    :portfolio
    |> Application.get_env(:album_catalog, [])
    |> Keyword.get(key, default)
  end
end
