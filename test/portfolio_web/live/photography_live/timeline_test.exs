defmodule PortfolioWeb.PhotographyLive.TimelineTest do
  @moduledoc """
  La chronologie est l'index des albums du portfolio.

  Elle lit le catalogue de la plateforme photo par le port : ce fichier
  éprouve ce qu'elle en fait, du chargement par tranches jusqu'à ce qu'elle
  affiche quand la plateforme ne répond plus.
  """

  # Le scénario de catalogue est un processus nommé, partagé par le noeud.
  use PortfolioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.CatalogFixtures

  alias Portfolio.Photography.Catalog.Decoder
  alias PortfolioTest.Support.ScriptedCatalogAdapter, as: Scenario

  setup %{conn: conn} do
    _ = Gettext.put_locale(PortfolioWeb.Gettext, "fr")
    {:ok, _pid} = Scenario.start_link()

    conn =
      conn
      |> Map.put(:host, "photo.thibaultsan.com")
      |> init_test_session(%{"locale" => "fr"})

    %{conn: conn}
  end

  defp page(albums) do
    {:ok, page} = Decoder.decode_album_list(album_list_response(albums: albums))
    page
  end

  defp publie(albums) do
    Scenario.script(:list_albums, {:ok, page(albums)})
  end

  defp albums(n, opts \\ []) do
    for numero <- 1..n do
      album_payload(
        Keyword.merge(
          [
            slug: "album-#{numero}",
            title: "Album #{numero}",
            shoot_date: Date.to_iso8601(Date.add(~D[2024-01-01], -numero)),
            shoot_end_date: nil
          ],
          opts
        )
      )
    end
  end

  describe "affichage" do
    test "rend la page même sans album", %{conn: conn} do
      publie([])

      {:ok, _vue, html} = live(conn, ~p"/timeline")

      assert html =~ "Thibault Santonja"
      assert html =~ "Accueil"
    end

    test "affiche le titre et la période de chaque album", %{conn: conn} do
      publie([
        album_payload(
          slug: "coucy",
          title: "Coucy a la Merveille",
          shoot_date: "2024-07-26",
          shoot_end_date: "2024-07-27"
        )
      ])

      {:ok, _vue, html} = live(conn, ~p"/timeline")

      assert html =~ "Coucy a la Merveille"
      assert html =~ "2024-07-26 - 2024-07-27"
    end

    test "affiche une date unique quand l'album n'a pas de date de fin", %{conn: conn} do
      publie([album_payload(shoot_date: "2024-07-26", shoot_end_date: nil)])

      {:ok, _vue, html} = live(conn, ~p"/timeline")

      assert html =~ "2024-07-26"
      refute html =~ "2024-07-26 - "
    end

    test "sert les variantes responsives de la couverture", %{conn: conn} do
      publie([album_payload(slug: "coucy")])

      {:ok, _vue, html} = live(conn, ~p"/timeline")

      assert html =~ "https://cdn.thibaultsan.com/variants/medium/photo.avif 800w"
      refute html =~ "?w=320&amp;q=75"
    end

    test "donne à la couverture le texte alternatif de la plateforme", %{conn: conn} do
      publie([
        album_payload(cover: photo_payload(alt: "Le donjon vu depuis la basse-cour"))
      ])

      {:ok, _vue, html} = live(conn, ~p"/timeline")

      assert html =~ "Le donjon vu depuis la basse-cour"
    end

    test "affiche le lien de référence quand l'album en porte un", %{conn: conn} do
      publie([album_payload(reference_url: "https://amvcc.test/coucy")])

      {:ok, vue, _html} = live(conn, ~p"/timeline")

      assert has_element?(vue, "a[href='https://amvcc.test/coucy']")
    end

    test "renvoie vers la page d'album", %{conn: conn} do
      publie([album_payload(slug: "coucy")])

      {:ok, vue, _html} = live(conn, ~p"/timeline")

      assert has_element?(vue, "a[href='/gallery/coucy']")
    end

    test "supporte un album sans date de prise de vue", %{conn: conn} do
      publie([album_payload(slug: "sans-date", shoot_date: nil, shoot_end_date: nil)])

      {:ok, _vue, html} = live(conn, ~p"/timeline")

      assert html =~ "Mariage de Claire et Damien"
    end

    test "supporte un album sans couverture", %{conn: conn} do
      publie([album_payload(slug: "sans-couverture", title: "Sans couverture", cover: nil)])

      {:ok, _vue, html} = live(conn, ~p"/timeline")

      assert html =~ "Sans couverture"
    end
  end

  describe "navigation par année" do
    test "liste les années des albums chargés", %{conn: conn} do
      publie([
        album_payload(slug: "a", shoot_date: "2023-06-15"),
        album_payload(slug: "b", shoot_date: "2024-06-15")
      ])

      {:ok, _vue, html} = live(conn, ~p"/timeline")

      assert html =~ "#year-2023"
      assert html =~ "#year-2024"
    end

    test "ne repete pas une année vue plusieurs fois", %{conn: conn} do
      publie([
        album_payload(slug: "a", shoot_date: "2024-01-15"),
        album_payload(slug: "b", shoot_date: "2024-06-15")
      ])

      {:ok, _vue, html} = live(conn, ~p"/timeline")

      assert html |> String.split("#year-2024") |> length() == 2
    end

    test "n'affiche aucune année quand aucun album n'en porte", %{conn: conn} do
      publie([album_payload(shoot_date: nil)])

      {:ok, _vue, html} = live(conn, ~p"/timeline")

      refute html =~ "#year-"
    end
  end

  describe "chargement par tranches" do
    test "charge vingt albums à l'ouverture", %{conn: conn} do
      publie(albums(25))

      {:ok, _vue, html} = live(conn, ~p"/timeline")

      assert html =~ "Album 1"
      assert html =~ "Album 20"
      refute html =~ "Album 21"
    end

    test "demande une entrée de plus que la tranche, pour savoir s'il en reste", %{conn: conn} do
      publie(albums(25))

      {:ok, _vue, _html} = live(conn, ~p"/timeline")

      assert Keyword.get(Scenario.last_args(:list_albums), :limit) == 21
      assert Keyword.get(Scenario.last_args(:list_albums), :offset) == 0
    end

    test "propose de charger la suite quand il reste des albums", %{conn: conn} do
      publie(albums(25))

      {:ok, vue, _html} = live(conn, ~p"/timeline")

      assert has_element?(vue, "#infinite-scroll-marker")
    end

    test "ne propose rien quand tout est charge", %{conn: conn} do
      publie(albums(10))

      {:ok, vue, _html} = live(conn, ~p"/timeline")

      refute has_element?(vue, "#infinite-scroll-marker")
    end

    test "charge la tranche suivante au décalage attendu", %{conn: conn} do
      publie(albums(25))
      {:ok, vue, _html} = live(conn, ~p"/timeline")

      publie([album_payload(slug: "suivant", title: "Album suivant")])
      html = render_hook(vue, "load_more", %{})

      assert html =~ "Album suivant"
      assert Keyword.get(Scenario.last_args(:list_albums), :offset) == 20
    end

    test "ne redemande rien une fois la dernière tranche atteinte", %{conn: conn} do
      publie(albums(10))
      {:ok, vue, _html} = live(conn, ~p"/timeline")
      appels = Scenario.calls(:list_albums)

      render_hook(vue, "load_more", %{})

      assert Scenario.calls(:list_albums) == appels
    end
  end

  describe "filtrage par thème" do
    test "transmet le thème demande à la plateforme", %{conn: conn} do
      publie([album_payload(slug: "coucy", title: "Coucy")])

      {:ok, _vue, _html} = live(conn, ~p"/timeline/reenactment")

      assert Keyword.get(Scenario.last_args(:list_albums), :theme) == "reenactment"
    end

    test "une page de thème ne coûte pas plus d'appels que la chronologie complète", %{conn: conn} do
      # Lire le catalogue avant de connaitre le chapitre, c'est lire la liste
      # non filtrée pour la jeter aussitôt : un aller-retour de plus vers la
      # plateforme et une entrée de cache de plus, par thème.
      publie([album_payload()])

      {:ok, _vue, _html} = live(conn, ~p"/timeline")
      complete = Scenario.calls(:list_albums)

      {:ok, _vue, _html} = live(conn, ~p"/timeline/reenactment")
      theme = Scenario.calls(:list_albums) - complete

      assert complete > 0, "sans appel du tout, l'égalité ne prouverait rien"
      assert theme == complete
    end

    test "ne transmet aucun thème sur la chronologie complète", %{conn: conn} do
      publie([album_payload()])

      {:ok, _vue, _html} = live(conn, ~p"/timeline")

      refute Keyword.has_key?(Scenario.last_args(:list_albums), :theme)
    end

    test "répond 404 pour un thème inconnu plutôt qu'une liste vide", %{conn: conn} do
      Scenario.script(:list_albums, {:error, :not_found})

      assert_error_sent 404, fn -> get(conn, "/timeline/nexiste-pas") end
    end

    test "une liste complète introuvable est une panne, pas un thème inconnu", %{conn: conn} do
      # Rien n'a été demandé qui puisse manquer : sans thème, un :not_found ne
      # peut venir que d'une plateforme en panne ou d'une adresse mal
      # configurée. La chronologie doit alors dégrader en 200, pas rendre 404.
      Scenario.script(:list_albums, {:error, :not_found})

      html = conn |> get("/timeline") |> html_response(200)

      assert html =~ "momentanément indisponible"
      assert html =~ "Thibault Santonja"
    end
  end

  describe "la plateforme ne répond pas" do
    test "affiche une page complète et un message explicite, en 200", %{conn: conn} do
      Scenario.script(:list_albums, {:error, :unavailable})

      html = conn |> get("/timeline") |> html_response(200)

      assert html =~ "momentanément indisponible"
      assert html =~ "Thibault Santonja"
    end

    test "ne propose pas de charger une suite qui n'existe pas", %{conn: conn} do
      Scenario.script(:list_albums, {:error, :unavailable})

      {:ok, vue, _html} = live(conn, ~p"/timeline")

      refute has_element?(vue, "#infinite-scroll-marker")
    end
  end

  describe "référencement" do
    test "la chronologie est exclue de l'index", %{conn: conn} do
      publie([album_payload()])

      conn = get(conn, "/timeline")

      assert get_resp_header(conn, "x-robots-tag") == ["noindex, follow"]
    end
  end

  describe "langue" do
    test "transmet la langue de la session à la plateforme", %{conn: conn} do
      publie([album_payload()])

      {:ok, _vue, _html} = live(conn, ~p"/timeline")

      assert Keyword.get(Scenario.last_args(:list_albums), :locale) == "fr"
    end

    test "propose le selecteur de langue", %{conn: conn} do
      publie([album_payload()])

      {:ok, vue, _html} = live(conn, ~p"/timeline")

      assert has_element?(vue, "button[phx-click='change_locale']")
    end
  end
end
