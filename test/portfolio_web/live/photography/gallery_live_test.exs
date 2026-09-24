defmodule PortfolioWeb.Photography.GalleryLiveTest do
  @moduledoc """
  Comportements de la page d'album, une fois l'album lu chez la plateforme.

  Le contenu et le référencement de cette page sont couverts par
  `PortfolioWeb.Photography.GalleryCatalogTest` ; ce fichier-ci garde la
  navigation, la langue et les métadonnées de page.
  """

  # Le scénario de catalogue est un processus nommé, partagé par le noeud.
  use PortfolioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.CatalogFixtures

  alias Portfolio.Photography.Catalog.Decoder
  alias PortfolioTest.Support.ScriptedCatalogAdapter, as: Scenario

  @hote "https://photo.thibaultsan.com"

  setup do
    {:ok, _pid} = Scenario.start_link()
    :ok
  end

  defp publie(opts) do
    {:ok, album} = Decoder.decode_album(album_detail_response(opts))
    Scenario.script(:get_album, {:ok, album})
    album
  end

  defp trois_photos do
    [
      photo_payload(id: "un", position: 1, alt: "Premiere", caption: "Legende une"),
      photo_payload(id: "deux", position: 2, alt: "Deuxieme", caption: "Legende deux"),
      photo_payload(id: "trois", position: 3, alt: "Troisieme", caption: "Legende trois")
    ]
  end

  describe "navigation" do
    test "l'accueil est joignable depuis la page d'album", %{conn: conn} do
      publie(slug: "un-album")

      {:ok, vue, _html} = live(conn, @hote <> "/gallery/un-album")

      vue
      |> element("a", "Accueil")
      |> render_click()
      |> follow_redirect(conn, ~p"/")
    end

    test "le chapitre china renvoie vers la chronologie filtree", %{conn: conn} do
      {:ok, vue, _html} = live(conn, @hote <> "/?chapter=china")

      vue
      |> element("a", "Voir plus")
      |> render_click()
      |> follow_redirect(conn, ~p"/timeline/china")
    end
  end

  describe "sélection d'une photo" do
    test "affiche la première photo par défaut", %{conn: conn} do
      publie(slug: "un-album", photos: trois_photos())

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/un-album")

      assert html =~ "Legende une"
    end

    test "affiche la photo demandée par le paramètre project", %{conn: conn} do
      publie(slug: "un-album", photos: trois_photos())

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/un-album?project=2")

      assert html =~ "Legende trois"
    end

    test "retombe sur la première photo quand l'index est hors limites", %{conn: conn} do
      publie(slug: "un-album", photos: trois_photos())

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/un-album?project=99")

      assert html =~ "Legende une"
    end

    test "retombe sur la première photo quand l'index n'est pas un nombre", %{conn: conn} do
      publie(slug: "un-album", photos: trois_photos())

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/un-album?project=abc")

      assert html =~ "Legende une"
    end

    test "parcourt les photos l'une après l'autre", %{conn: conn} do
      publie(slug: "un-album", photos: trois_photos())

      {:ok, vue, _html} = live(conn, @hote <> "/gallery/un-album")

      assert render_click(vue, "show_project", %{"project" => "1"}) =~ "Legende deux"
      assert render_click(vue, "show_project", %{"project" => "2"}) =~ "Legende trois"
      assert render_click(vue, "show_project", %{"project" => "0"}) =~ "Legende une"
    end
  end

  describe "compteur de photos" do
    test "annonce le nombre de photos de l'album", %{conn: conn} do
      publie(slug: "un-album", photos: trois_photos())

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/un-album")

      assert html =~ "(1 - 3)"
    end
  end

  describe "métadonnées de page" do
    test "le titre porte le nom de l'album", %{conn: conn} do
      publie(slug: "un-album", title: "Sortie de ceremonie")

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/un-album")

      assert html =~ "Sortie de ceremonie"
    end

    test "la description de page reprend celle de l'album", %{conn: conn} do
      publie(slug: "un-album", description: "Une journee de juin au chateau")

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/un-album")

      assert html =~ ~s(name="description" content="Une journee de juin au chateau")
    end

    test "la description de page retombe sur le titre quand l'album n'en a pas", %{conn: conn} do
      publie(slug: "un-album", title: "Sans description", description: nil)

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/un-album")

      assert html =~ ~s(name="description" content="Sans description")
    end
  end

  describe "langue" do
    test "suit le cookie de langue", %{conn: conn} do
      publie(slug: "un-album")
      conn = put_req_cookie(conn, "locale", "en")

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/un-album")

      assert html =~ "Home"
    end

    test "suit le paramètre d'URL quand il est fourni", %{conn: conn} do
      publie(slug: "un-album")

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/un-album?hl=en")

      assert html =~ "Home"
    end

    test "sert le francais par défaut", %{conn: conn} do
      publie(slug: "un-album")

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/un-album")

      assert html =~ "Accueil"
    end

    test "transmet la langue demandée à la plateforme", %{conn: conn} do
      publie(slug: "un-album")

      {:ok, _vue, _html} = live(conn, @hote <> "/gallery/un-album?hl=en")

      assert {"un-album", opts} = Scenario.last_args(:get_album)
      assert Keyword.get(opts, :locale) == "en"
    end
  end
end
