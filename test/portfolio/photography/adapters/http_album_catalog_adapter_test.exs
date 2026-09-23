defmodule Portfolio.Photography.Adapters.HttpAlbumCatalogAdapterTest do
  use ExUnit.Case, async: true

  import PortfolioTest.Fixtures.CatalogFixtures

  alias Portfolio.Photography.Adapters.HttpAlbumCatalogAdapter
  alias Portfolio.Photography.Catalog.Album

  defp stub(fun) do
    Req.Test.stub(HttpAlbumCatalogAdapter, fun)
  end

  describe "list_albums/1" do
    test "appelle /api/v1/albums et decode la reponse" do
      stub(fn conn ->
        assert conn.request_path == "/api/v1/albums"
        Req.Test.json(conn, album_list_response())
      end)

      assert {:ok, %{albums: [%Album{slug: "mariage-claire-et-damien"}], meta: meta}} =
               HttpAlbumCatalogAdapter.list_albums([])

      assert meta.total == 1
    end

    test "transmet theme, locale, limit et offset en parametres de requete" do
      stub(fn conn ->
        params = URI.decode_query(conn.query_string)

        assert params == %{
                 "theme" => "wedding",
                 "locale" => "en",
                 "limit" => "12",
                 "offset" => "24"
               }

        Req.Test.json(conn, album_list_response(albums: []))
      end)

      assert {:ok, %{albums: []}} =
               HttpAlbumCatalogAdapter.list_albums(
                 theme: "wedding",
                 locale: "en",
                 limit: 12,
                 offset: 24
               )
    end

    test "omet les parametres non renseignes plutot que d'envoyer des valeurs vides" do
      stub(fn conn ->
        assert conn.query_string == ""
        Req.Test.json(conn, album_list_response(albums: []))
      end)

      assert {:ok, _page} =
               HttpAlbumCatalogAdapter.list_albums(theme: nil, locale: nil, limit: nil)
    end

    test "traduit un 404 en :not_found" do
      stub(fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"error" => %{"code" => "not_found", "message" => "theme inconnu"}})
      end)

      assert {:error, :not_found} = HttpAlbumCatalogAdapter.list_albums(theme: "inexistant")
    end

    test "traduit une erreur serveur en :unavailable" do
      stub(fn conn ->
        conn
        |> Plug.Conn.put_status(503)
        |> Req.Test.json(%{"error" => %{"code" => "unavailable"}})
      end)

      assert {:error, :unavailable} = HttpAlbumCatalogAdapter.list_albums([])
    end

    test "traduit une panne de transport en :unavailable" do
      stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, :unavailable} = HttpAlbumCatalogAdapter.list_albums([])
    end

    test "traduit une reponse hors contrat en :unavailable" do
      stub(fn conn -> Req.Test.json(conn, %{"data" => %{"pas" => "une liste"}}) end)

      assert {:error, :unavailable} = HttpAlbumCatalogAdapter.list_albums([])
    end

    test "n'effectue aucune reprise dans le chemin de la requete" do
      counter = :counters.new(1, [])

      stub(fn conn ->
        :counters.add(counter, 1, 1)
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, :unavailable} = HttpAlbumCatalogAdapter.list_albums([])
      assert :counters.get(counter, 1) == 1
    end
  end

  describe "get_album/2" do
    test "appelle /api/v1/albums/:slug et decode l'album complet" do
      stub(fn conn ->
        assert conn.request_path == "/api/v1/albums/mariage-claire-et-damien"
        Req.Test.json(conn, album_detail_response())
      end)

      assert {:ok, %Album{slug: "mariage-claire-et-damien", photos: [photo]}} =
               HttpAlbumCatalogAdapter.get_album("mariage-claire-et-damien")

      assert photo.alt != ""
    end

    test "encode le slug dans le chemin" do
      stub(fn conn ->
        assert conn.request_path == "/api/v1/albums/un%2Fslug"
        Plug.Conn.send_resp(conn, 404, "{}")
      end)

      assert {:error, :not_found} = HttpAlbumCatalogAdapter.get_album("un/slug")
    end

    test "traduit un album absent ou non publie en :not_found" do
      stub(fn conn -> Plug.Conn.send_resp(conn, 404, ~s({"error":{"code":"not_found"}})) end)

      assert {:error, :not_found} = HttpAlbumCatalogAdapter.get_album("brouillon")
    end
  end

  describe "list_themes/1" do
    test "appelle /api/v1/themes et decode les themes" do
      stub(fn conn ->
        assert conn.request_path == "/api/v1/themes"
        Req.Test.json(conn, theme_list_response())
      end)

      assert {:ok, [wedding, _reenactment]} = HttpAlbumCatalogAdapter.list_themes()
      assert wedding.slug == "wedding"
    end

    test "traduit une panne de transport en :unavailable" do
      stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, :unavailable} = HttpAlbumCatalogAdapter.list_themes()
    end
  end
end
