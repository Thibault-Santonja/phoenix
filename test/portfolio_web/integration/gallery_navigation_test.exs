defmodule PortfolioWeb.Integration.GalleryNavigationTest do
  @moduledoc """
  Parcours de bout en bout sur `photo.thibaultsan.com` : de la chronologie a
  un album, et retour.

  Les albums viennent de la plateforme photo, lus par le port. Ce fichier
  verifie l'enchainement des pages ; le detail de chaque page est couvert par
  `PortfolioWeb.PhotographyLive.TimelineTest` et
  `PortfolioWeb.Photography.GalleryCatalogTest`.
  """

  # Le scenario de catalogue est un processus nomme, partage par le noeud.
  use PortfolioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.CatalogFixtures

  alias Portfolio.Photography.Catalog.Decoder
  alias PortfolioTest.Support.ScriptedCatalogAdapter, as: Scenario

  setup %{conn: conn} do
    _ = Gettext.put_locale(PortfolioWeb.Gettext, "fr")
    {:ok, _pid} = Scenario.start_link()

    %{conn: Map.put(conn, :host, "photo.thibaultsan.com")}
  end

  defp publie_catalogue(slug, titre) do
    {:ok, page} =
      Decoder.decode_album_list(
        album_list_response(albums: [album_payload(slug: slug, title: titre)])
      )

    {:ok, album} = Decoder.decode_album(album_detail_response(slug: slug, title: titre))

    Scenario.script(:list_albums, {:ok, page})
    Scenario.script(:get_album, {:ok, album})
  end

  describe "de la chronologie a l'album" do
    test "la chronologie mene a la page d'album", %{conn: conn} do
      publie_catalogue("coucy-a-la-merveille", "Coucy a la Merveille")

      {:ok, chronologie, _html} = live(conn, ~p"/timeline")

      lien =
        chronologie
        |> element("a[href='/gallery/coucy-a-la-merveille']")
        |> render()

      assert lien =~ "/gallery/coucy-a-la-merveille"

      {:ok, _album, html} = live(conn, ~p"/gallery/coucy-a-la-merveille")

      assert html =~ "Coucy a la Merveille"
    end

    test "la page d'album ramene a la chronologie", %{conn: conn} do
      publie_catalogue("coucy-a-la-merveille", "Coucy a la Merveille")

      {:ok, album, _html} = live(conn, ~p"/gallery/coucy-a-la-merveille")

      album
      |> element("button", "Retour")
      |> render_click()
      |> follow_redirect(conn, ~p"/timeline")
    end
  end

  describe "ce qui n'est pas publie" do
    test "un album non publie est indiscernable d'un album inexistant", %{conn: conn} do
      Scenario.script(:get_album, {:error, :not_found})

      assert_error_sent 404, fn -> get(conn, "/gallery/brouillon-secret") end
    end
  end

  describe "la plateforme ne repond pas" do
    test "les deux pages restent completes et sans erreur", %{conn: conn} do
      Scenario.script(:list_albums, {:error, :unavailable})
      Scenario.script(:get_album, {:error, :unavailable})

      chronologie = get(conn, "/timeline")
      album = get(conn, "/gallery/un-album")

      assert html_response(chronologie, 200) =~ "momentanément indisponible"
      assert html_response(album, 200) =~ "momentanément indisponible"
    end
  end

  describe "langue" do
    test "la langue choisie suit d'une page a l'autre", %{conn: conn} do
      publie_catalogue("coucy-a-la-merveille", "Coucy a la Merveille")
      conn = put_req_cookie(conn, "locale", "en")

      {:ok, _chronologie, chronologie_html} = live(conn, ~p"/timeline")
      {:ok, _album, album_html} = live(conn, ~p"/gallery/coucy-a-la-merveille")

      assert chronologie_html =~ "Home"
      assert album_html =~ "Home"
    end
  end
end
