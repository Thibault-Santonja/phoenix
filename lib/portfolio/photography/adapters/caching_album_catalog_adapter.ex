defmodule Portfolio.Photography.Adapters.CachingAlbumCatalogAdapter do
  @moduledoc """
  Décorateur de cache et échelle de dégradation devant un autre adaptateur de
  catalogue.

  Il implémente le même port que l'adaptateur qu'il enveloppe : la couche web
  ne sait pas qu'il existe. Sa seule promesse tient en une phrase : le
  visiteur ne voit jamais de page vide et jamais d'erreur, même plateforme
  éteinte.

  ## Les quatre paliers

  1. **Cache frais** (moins de `:fresh_for_ms`, dix minutes par défaut) :
     réponse immédiate, aucun appel réseau.
  2. **Cache périmé** : le contenu périmé part immédiatement, et un
     rafraîchissement est lancé hors du chemin de la requête, un seul en vol
     par clé. C'est le `stale-while-revalidate` du cache HTTP, appliqué ici.
  3. **Cache vide et plateforme muette** : relecture de l'instantané sur
     disque. C'est le palier du redémarrage de l'hôte, où les deux
     applications repartent ensemble et où le portfolio, plus léger, est prêt
     avant la plateforme.
  4. **Rien du tout** : `{:error, :unavailable}`. La couche web affiche alors
     sa navigation statique et le dit explicitement au visiteur, en 200.

  ## Ce qui n'est jamais mis en cache

  Les erreurs. Un échec ne remplace pas une entrée valide : il la laisse
  vieillir. Un `:not_found` n'est pas mis en cache non plus, sinon la
  publication d'un album resterait invisible jusqu'à expiration.

  ## Instantané

  Seules la liste d'albums et la liste des thèmes sont conservées sur disque :
  ce sont les deux pages dont le vide serait inacceptable. Une fiche d'album
  indisponible retombe sur la liste, ce qui est acceptable.

  ## Mémoire

  Le cache vit dans son propre espace Cachex (`:catalog_cache`), plafonné à
  cent entrées. La mesure, et non l'estimation, donne 2,2 kilo-octets par
  photo décodée avec ses neuf sources : les URL dominent la structure. Le
  fichier `test/portfolio/photography/catalog/memory_budget_test.exs` garde
  ce chiffre et le plafond de vingt mégaoctets pour cent entrées.

  ## Invalidation

  `invalidate_all/0` vide le cache et les instantanés. C'est ce que la
  procédure de retrait de consentement doit appeler : sans elle, un album
  dépublié resterait visible jusqu'au prochain rafraîchissement.
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
  Vide le cache mémoire et les instantanés sur disque.

  À appeler lors d'un retrait de consentement ou de toute dépublication qui
  ne peut pas attendre le prochain rafraîchissement.
  """
  @spec invalidate_all() :: :ok
  def invalidate_all do
    _ = Cachex.clear(@cache)
    efface_instantanes(snapshot_dir())
  end

  defp efface_instantanes(nil), do: :ok

  defp efface_instantanes(dir) do
    {:ok, _supprimes} = File.rm_rf(dir)
    :ok
  end

  # ============================================================================
  # Échelle de dégradation
  # ============================================================================

  defp read(key, opts) do
    case cached(key) do
      {:hit, value, age_ms} ->
        # Comparaison stricte : une fenêtre de fraîcheur à zéro milliseconde
        # signifie « revalide à chaque lecture », ce qui est une configuration
        # légitime et pas un cas dégénéré.
        #
        # Dans les deux cas la valeur en cache part immédiatement : le
        # rafraîchissement ne retarde jamais une réponse.
        if age_ms >= fresh_for_ms(), do: schedule_refresh(key, opts)
        {:ok, value}

      :miss ->
        fetch_now(key, opts)
    end
  end

  defp fetch_now(key, opts) do
    case Keyword.fetch!(opts, :fetch).() do
      {:ok, value} ->
        :ok = store(key, value, fresh?: true)
        :ok = write_snapshot(key, value, opts)
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
      # L'instantané est par nature périmé : on le stocke comme tel, pour que
      # la requête suivante déclenche un rafraîchissement en tâche de fond.
      :ok = store(key, value, fresh?: false)
      {:ok, value}
    else
      _autre -> {:error, :unavailable}
    end
  end

  defp schedule_refresh(key, opts) do
    # Le verrou passe par `Cachex.fetch/3` : la bibliothèque garantit qu'une
    # seule exécution de la fonction est en vol pour une clé donnée, ce qui
    # évite d'écrire un verrou à la main.
    _ =
      Task.Supervisor.start_child(Portfolio.TaskSupervisor, fn ->
        Cachex.fetch(@cache, {:refreshing, key}, fn ->
          :ok = refresh(key, opts)
          {:commit, :en_cours, expire: @refresh_lock_ms}
        end)
      end)

    :ok
  end

  # Rend `:ok` : `:telemetry.execute/3` est la dernière expression, et
  # `schedule_refresh/2` apparie ce retour.
  defp refresh(key, opts) do
    resultat =
      case Keyword.fetch!(opts, :fetch).() do
        {:ok, value} ->
          :ok = store(key, value, fresh?: true)
          :ok = write_snapshot(key, value, opts)
          :ok

        {:error, reason} ->
          # L'entrée périmée reste en place : un échec ne remplace jamais une
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

  # Rend toujours `:ok` : un cache indisponible ne doit pas faire échouer une
  # lecture, il la rend simplement plus coûteuse.
  defp store(key, value, fresh?: true) do
    put(key, value, System.monotonic_time(:millisecond))
  end

  defp store(key, value, fresh?: false) do
    put(key, value, System.monotonic_time(:millisecond) - fresh_for_ms() - 1)
  end

  defp put(key, value, stored_at) do
    _ = Cachex.put(@cache, key, %{value: value, stored_at: stored_at})
    :ok
  end

  # ============================================================================
  # Instantané
  # ============================================================================

  # Rend toujours `:ok` : un instantané est un filet, son échec d'écriture est
  # journalisé par `Snapshot` et ne doit rien interrompre.
  defp write_snapshot(key, value, opts) do
    case Keyword.get(opts, :to_payload) do
      nil -> :ok
      to_payload -> ecrit(key, to_payload.(value))
    end
  end

  defp ecrit(key, payload) do
    _ = Snapshot.write(snapshot_dir(), key, payload)
    :ok
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
