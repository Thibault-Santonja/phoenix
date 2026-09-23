defmodule PortfolioWeb.Photography.GalleryCatalogTest do
  @moduledoc """
  La page d'album lit le catalogue de la plateforme photo.

  Deux exigences priment sur les autres : le visiteur ne voit jamais de page
  vide ni d'erreur quand la plateforme ne répond pas, et la page désigne
  toujours la plateforme comme adresse de référence.
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

  describe "un album publié" do
    test "affiche le titre de l'album et le nombre de photos", %{conn: conn} do
      publie(
        slug: "coucy-a-la-merveille",
        title: "Coucy a la Merveille",
        photos: [
          photo_payload(id: "un", position: 1, alt: "Le donjon au crepuscule"),
          photo_payload(id: "deux", position: 2, alt: "Le public sous les remparts")
        ]
      )

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/coucy-a-la-merveille")

      assert html =~ "Coucy a la Merveille"
      assert html =~ "Le donjon au crepuscule"
    end

    test "sert les variantes responsives de la plateforme, pas des URL fabriquées", %{conn: conn} do
      publie(slug: "coucy-a-la-merveille")

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/coucy-a-la-merveille")

      assert html =~ "https://cdn.thibaultsan.com/variants/large/photo.avif 1600w"
      assert html =~ "https://cdn.thibaultsan.com/variants/large/photo.jpeg"
      # L'ancienne page fabriquait des URL à coups de paramètres de requête que
      # rien ne sert.
      refute html =~ "?w=320&amp;q=80"
    end

    test "réserve la place de la photo avant son chargement", %{conn: conn} do
      publie(slug: "coucy", photos: [photo_payload(width: 6000, height: 4000)])

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/coucy")

      assert html =~ "aspect-ratio: 6000 / 4000"
    end

    test "pose la canonique fournie par l'API, sans la reconstruire", %{conn: conn} do
      publie(slug: "coucy-a-la-merveille")

      conn = get(Map.put(conn, :host, "photo.thibaultsan.com"), "/gallery/coucy-a-la-merveille")
      html = html_response(conn, 200)

      assert html =~
               ~s(href="https://photography.thibaultsan.com/albums/coucy-a-la-merveille")

      assert get_resp_header(conn, "x-robots-tag") == ["noindex, follow"]
    end

    test "donne à chaque image un texte alternatif issu de la plateforme", %{conn: conn} do
      publie(
        slug: "coucy-a-la-merveille",
        photos: [photo_payload(alt: "Une joueuse de vielle a roue devant le feu")]
      )

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/coucy-a-la-merveille")

      assert html =~ "Une joueuse de vielle a roue devant le feu"
    end

    test "change de photo sans rappeler la plateforme", %{conn: conn} do
      publie(
        slug: "coucy-a-la-merveille",
        photos: [
          photo_payload(id: "un", position: 1, alt: "Premiere image"),
          photo_payload(id: "deux", position: 2, alt: "Seconde image")
        ]
      )

      {:ok, vue, _html} = live(conn, @hote <> "/gallery/coucy-a-la-merveille")
      appels = Scenario.calls(:get_album)

      html = render_click(vue, "show_project", %{"project" => "1"})

      assert html =~ "Seconde image"
      assert Scenario.calls(:get_album) == appels
    end
  end

  describe "la plateforme ne répond pas" do
    test "affiche une page complète plutôt qu'une page vide", %{conn: conn} do
      Scenario.script(:get_album, {:error, :unavailable})

      conn = get(Map.put(conn, :host, "photo.thibaultsan.com"), "/gallery/un-album")
      html = html_response(conn, 200)

      assert html =~ "momentanément indisponible"
      assert html =~ "/timeline"
    end

    test "ne rend ni 500 ni page blanche", %{conn: conn} do
      Scenario.script(:get_album, {:error, :unavailable})

      {:ok, _vue, html} = live(conn, @hote <> "/gallery/un-album")

      refute html == ""
      assert html =~ "Thibault San"
    end
  end

  describe "album inconnu" do
    test "répond 404 plutôt que d'inventer un contenu", %{conn: conn} do
      Scenario.script(:get_album, {:error, :not_found})

      assert_error_sent 404, fn ->
        get(Map.put(conn, :host, "photo.thibaultsan.com"), "/gallery/jamais-publie")
      end
    end
  end

  describe "paramètre de langue" do
    test "ne relaie pas une langue que le portfolio ne parle pas", %{conn: conn} do
      # `hl` est le paramètre de langue de Google : un lien partagé peut
      # porter n'importe quoi. Relayé tel quel, il vaut un 400 de la
      # plateforme, donc une page « momentanément indisponible » à la place de
      # l'album, et une clé de cache de plus par valeur distincte.
      publie(slug: "coucy")

      {:ok, _vue, _html} = live(conn, @hote <> "/gallery/coucy?hl=fr-FR")

      {_slug, opts} = Scenario.last_args(:get_album)
      assert Keyword.get(opts, :locale) == "fr"
    end

    test "relaie une langue effectivement servie", %{conn: conn} do
      publie(slug: "coucy")

      {:ok, _vue, _html} = live(conn, @hote <> "/gallery/coucy?hl=en")

      {_slug, opts} = Scenario.last_args(:get_album)
      assert Keyword.get(opts, :locale) == "en"
    end
  end

  describe "/gallery sans album" do
    test "renvoie vers la chronologie, qui est l'index des albums", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/timeline"}}} = live(conn, @hote <> "/gallery")
    end
  end
end
