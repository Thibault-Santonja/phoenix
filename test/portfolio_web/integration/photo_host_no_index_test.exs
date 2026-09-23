defmodule PortfolioWeb.Integration.PhotoHostNoIndexTest do
  @moduledoc """
  La seule protection du portfolio contre le contenu dupliqué.

  `photo.thibaultsan.com` et la plateforme photo servent le même catalogue.
  Si ces assertions tombent, les deux adresses se font concurrence dans
  l'index et le moteur choisit lui-même laquelle presenter.
  """

  use PortfolioWeb.ConnCase, async: true

  @photo "https://photo.thibaultsan.com"
  @plateforme "https://photography.thibaultsan.com"

  defp photo_conn(conn, chemin) do
    conn
    |> Map.put(:host, "photo.thibaultsan.com")
    |> get(chemin)
  end

  describe "pages servies sous photo." do
    test "l'accueil porte la directive noindex en en-tete HTTP", %{conn: conn} do
      conn = photo_conn(conn, "/")

      assert get_resp_header(conn, "x-robots-tag") == ["noindex, follow"]
    end

    test "l'accueil porte la balise meta robots", %{conn: conn} do
      html = conn |> photo_conn("/") |> html_response(200)

      assert html =~ ~s(<meta name="robots" content="noindex, follow">)
    end

    test "l'accueil pointe sa canonique vers la plateforme", %{conn: conn} do
      html = conn |> photo_conn("/") |> html_response(200)

      assert html =~ ~s(rel="canonical")
      assert html =~ @plateforme
      refute html =~ ~s(<link rel="canonical" href="#{@photo}/">)
    end

    test "og:url désigne la plateforme, pour qu'un partage y ramene", %{conn: conn} do
      html = conn |> photo_conn("/") |> html_response(200)

      assert html =~ ~s(<meta property="og:url" content="#{@plateforme}">)
    end

    test "aucune annonce hreflang ne contredit la canonique", %{conn: conn} do
      html = conn |> photo_conn("/") |> html_response(200)

      refute html =~ "hreflang"
    end

    test "la galerie porte aussi la directive", %{conn: conn} do
      conn = photo_conn(conn, "/gallery")

      assert get_resp_header(conn, "x-robots-tag") == ["noindex, follow"]
    end

    test "la chronologie porte aussi la directive", %{conn: conn} do
      conn = photo_conn(conn, "/timeline")

      assert get_resp_header(conn, "x-robots-tag") == ["noindex, follow"]
    end
  end

  describe "plans de site" do
    test "sitemap.xml répond 404 sous photo.", %{conn: conn} do
      conn = photo_conn(conn, "/sitemap.xml")

      assert conn.status == 404
    end

    test "image-sitemap.xml répond 404 sous photo.", %{conn: conn} do
      conn = photo_conn(conn, "/image-sitemap.xml")

      assert conn.status == 404
    end

    test "sitemap.xml reste servi sur l'hôte principal", %{conn: conn} do
      conn =
        conn
        |> Map.put(:host, "thibaultsan.com")
        |> put_req_header("accept", "application/xml")
        |> get("/sitemap.xml")

      assert conn.status == 200
    end
  end

  describe "robots.txt" do
    test "n'interdit pas l'exploration, sinon la directive noindex ne serait jamais lue" do
      contenu = File.read!(Path.join(:code.priv_dir(:portfolio), "static/robots.txt"))

      refute contenu =~ ~r/^Disallow:\s*\/\s*$/m
    end
  end
end
