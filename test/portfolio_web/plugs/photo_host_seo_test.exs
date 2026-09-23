defmodule PortfolioWeb.Plugs.PhotoHostSeoTest do
  use PortfolioWeb.ConnCase, async: true

  alias PortfolioWeb.Plugs.PhotoHostSeo

  defp appelle(host) do
    :get
    |> Phoenix.ConnTest.build_conn("/")
    |> Map.put(:host, host)
    |> PhotoHostSeo.call(PhotoHostSeo.init([]))
  end

  describe "sur l'hote photo." do
    test "pose l'en-tete X-Robots-Tag noindex, follow" do
      conn = appelle("photo.thibaultsan.com")

      assert get_resp_header(conn, "x-robots-tag") == ["noindex, follow"]
    end

    test "expose la directive aux gabarits pour la balise meta" do
      conn = appelle("photo.thibaultsan.com")

      assert conn.assigns.robots == "noindex, follow"
    end

    test "pose une canonique par defaut vers la plateforme photo" do
      conn = appelle("photo.thibaultsan.com")

      assert conn.assigns.canonical_url == "https://photography.thibaultsan.com"
    end
  end

  describe "sur les autres hotes du portfolio" do
    test "ne desindexe pas thibaultsan.com" do
      conn = appelle("thibaultsan.com")

      assert get_resp_header(conn, "x-robots-tag") == []
      refute Map.has_key?(conn.assigns, :robots)
    end

    test "ne desindexe pas tech." do
      conn = appelle("tech.thibaultsan.com")

      assert get_resp_header(conn, "x-robots-tag") == []
    end
  end
end
