defmodule Portfolio.Photography.Adapters.CachingAlbumCatalogAdapterTest do
  # Le cache Cachex est un espace partagé par le noeud : ces tests ne peuvent
  # pas tourner en parallele des autres.
  use ExUnit.Case, async: false

  import PortfolioTest.Fixtures.CatalogFixtures

  alias Portfolio.Photography.Adapters.CachingAlbumCatalogAdapter, as: Cache
  alias Portfolio.Photography.Catalog.Album
  alias Portfolio.Photography.Catalog.Decoder
  alias Portfolio.Photography.Catalog.Snapshot
  alias PortfolioTest.Support.ScriptedCatalogAdapter, as: Scenario

  @telemetrie [:portfolio, :catalog, :refresh]

  setup context do
    {:ok, _pid} = Scenario.start_link()
    {:ok, _} = Cachex.clear(:catalog_cache)

    dir =
      if context[:instantane] do
        chemin = Path.join(System.tmp_dir!(), "catalog-#{System.unique_integer([:positive])}")
        on_exit(fn -> File.rm_rf!(chemin) end)
        chemin
      end

    configure(fresh_for_ms: context[:fresh_for_ms] || :timer.minutes(10), snapshot_dir: dir)

    test_pid = self()
    handler = "catalog-refresh-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      @telemetrie,
      fn _event, _mesures, metadata, _config ->
        send(test_pid, {:refresh, metadata.outcome})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler)
      restore()
    end)

    %{dir: dir}
  end

  defp configure(opts) do
    base = Application.get_env(:portfolio, :album_catalog, [])

    Application.put_env(
      :portfolio,
      :album_catalog,
      Keyword.merge(base, Keyword.put(opts, :inner_adapter, Scenario))
    )
  end

  defp restore do
    Application.put_env(
      :portfolio,
      :album_catalog,
      Keyword.merge(Application.get_env(:portfolio, :album_catalog, []),
        fresh_for_ms: :timer.minutes(10),
        snapshot_dir: nil
      )
    )
  end

  defp page(slug) do
    {:ok, page} =
      Decoder.decode_album_list(album_list_response(albums: [album_payload(slug: slug)]))

    page
  end

  describe "palier 1 : cache frais" do
    test "ne touche pas au réseau sur la seconde lecture" do
      Scenario.script(:list_albums, {:ok, page("premier")})

      assert {:ok, %{albums: [%Album{slug: "premier"}]}} = Cache.list_albums([])
      assert {:ok, %{albums: [%Album{slug: "premier"}]}} = Cache.list_albums([])

      assert Scenario.calls(:list_albums) == 1
    end

    test "separe les entrées par thème, locale, limite et décalage" do
      Scenario.script(:list_albums, {:ok, page("un")})
      assert {:ok, _} = Cache.list_albums(theme: "wedding")

      Scenario.script(:list_albums, {:ok, page("deux")})
      assert {:ok, %{albums: [%Album{slug: "deux"}]}} = Cache.list_albums(theme: "street")

      assert Scenario.calls(:list_albums) == 2
    end
  end

  describe "palier 2 : cache périmé, rafraîchissement hors du chemin de la requête" do
    @tag fresh_for_ms: 0
    test "sert le contenu périmé immédiatement et rafraîchit en tâche de fond" do
      Scenario.script(:list_albums, {:ok, page("ancien")})
      assert {:ok, %{albums: [%Album{slug: "ancien"}]}} = Cache.list_albums([])

      Scenario.script(:list_albums, {:ok, page("nouveau")})

      # La requête rend le contenu périmé, pas le nouveau : aucun appel réseau
      # n'a lieu dans le chemin de la requête.
      assert {:ok, %{albums: [%Album{slug: "ancien"}]}} = Cache.list_albums([])

      assert_receive {:refresh, :ok}, 1_000
      assert {:ok, %{albums: [%Album{slug: "nouveau"}]}} = Cache.list_albums([])
    end

    @tag fresh_for_ms: 0
    test "conserve le contenu périmé quand le rafraîchissement échoue" do
      Scenario.script(:list_albums, {:ok, page("ancien")})
      assert {:ok, _} = Cache.list_albums([])

      Scenario.script(:list_albums, {:error, :unavailable})
      assert {:ok, %{albums: [%Album{slug: "ancien"}]}} = Cache.list_albums([])

      assert_receive {:refresh, :unavailable}, 1_000

      # L'échec n'a pas remplace l'entrée valide : elle vieillit, elle ne
      # disparait pas.
      assert {:ok, %{albums: [%Album{slug: "ancien"}]}} = Cache.list_albums([])
    end
  end

  describe "palier 3 : cache vide et plateforme muette" do
    @tag :instantane
    test "relit l'instantané écrit au dernier rafraîchissement réussi", %{dir: dir} do
      Scenario.script(:list_albums, {:ok, page("depuis-instantane")})
      assert {:ok, _} = Cache.list_albums([])
      assert {:ok, _payload} = Snapshot.read(dir, {:albums, {nil, nil, nil, nil}})

      # Redémarrage : le cache mémoire repart vide, la plateforme est muette.
      {:ok, _} = Cachex.clear(:catalog_cache)
      Scenario.script(:list_albums, {:error, :unavailable})

      assert {:ok, %{albums: [%Album{slug: "depuis-instantane"}]}} = Cache.list_albums([])
    end

    @tag :instantane
    test "conserve aussi les thèmes sur disque", %{dir: dir} do
      {:ok, themes} = Decoder.decode_theme_list(theme_list_response())
      Scenario.script(:list_themes, {:ok, themes})
      assert {:ok, _} = Cache.list_themes()
      assert {:ok, _payload} = Snapshot.read(dir, {:themes, nil})

      {:ok, _} = Cachex.clear(:catalog_cache)
      Scenario.script(:list_themes, {:error, :unavailable})

      assert {:ok, [%{slug: "wedding"} | _]} = Cache.list_themes()
    end

    @tag :instantane
    test "ne conserve pas les fiches d'album sur disque", %{dir: dir} do
      {:ok, album} = Decoder.decode_album(album_detail_response())
      Scenario.script(:get_album, {:ok, album})
      assert {:ok, _} = Cache.get_album("mariage-claire-et-damien")

      assert Snapshot.read(dir, {:album, "mariage-claire-et-damien", nil}) == :error
    end

    @tag :instantane
    test "l'instantané relu est traite comme périmé et déclenche un rafraîchissement" do
      Scenario.script(:list_albums, {:ok, page("depuis-instantane")})
      assert {:ok, _} = Cache.list_albums([])

      {:ok, _} = Cachex.clear(:catalog_cache)
      Scenario.script(:list_albums, {:error, :unavailable})
      assert {:ok, _} = Cache.list_albums([])

      Scenario.script(:list_albums, {:ok, page("rafraichi")})
      assert {:ok, %{albums: [%Album{slug: "depuis-instantane"}]}} = Cache.list_albums([])

      assert_receive {:refresh, :ok}, 1_000
      assert {:ok, %{albums: [%Album{slug: "rafraichi"}]}} = Cache.list_albums([])
    end
  end

  describe "palier 4 : plus rien" do
    test "signale l'indisponibilité plutôt que de rendre une liste vide" do
      Scenario.script(:list_albums, {:error, :unavailable})

      assert {:error, :unavailable} = Cache.list_albums([])
    end

    test "ne met jamais une erreur en cache" do
      Scenario.script(:list_albums, {:error, :unavailable})
      assert {:error, :unavailable} = Cache.list_albums([])

      Scenario.script(:list_albums, {:ok, page("revenu")})
      assert {:ok, %{albums: [%Album{slug: "revenu"}]}} = Cache.list_albums([])
    end
  end

  describe "get_album/2" do
    test "ne met pas en cache un album absent" do
      Scenario.script(:get_album, {:error, :not_found})
      assert {:error, :not_found} = Cache.get_album("pas-encore-publie")

      {:ok, album} = Decoder.decode_album(album_detail_response(slug: "pas-encore-publie"))
      Scenario.script(:get_album, {:ok, album})

      assert {:ok, %Album{slug: "pas-encore-publie"}} = Cache.get_album("pas-encore-publie")
    end

    test "ne retombe pas sur un instantané pour une fiche" do
      Scenario.script(:get_album, {:error, :unavailable})

      assert {:error, :unavailable} = Cache.get_album("mariage-claire-et-damien")
    end
  end

  describe "invalidate_all/0" do
    @tag :instantane
    test "efface le cache mémoire et les instantanés", %{dir: dir} do
      Scenario.script(:list_albums, {:ok, page("a-retirer")})
      assert {:ok, _} = Cache.list_albums([])
      assert File.dir?(dir)

      assert :ok = Cache.invalidate_all()

      refute File.dir?(dir)
      Scenario.script(:list_albums, {:error, :unavailable})
      assert {:error, :unavailable} = Cache.list_albums([])
    end
  end
end
