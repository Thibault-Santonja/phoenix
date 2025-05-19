defmodule PortfolioWeb do
  use PortfolioWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "SEO files" do
    test "GET /robots.txt", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")

      assert response_content_type(conn, :html)
      assert response(conn, 200) =~ "User-agent: *"
    end

    test "GET /sitemap.xml accesses the sitemap in format xml", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")

      assert response_content_type(conn, :xml)
      assert response(conn, 200) =~ ~r/<loc>https:\/\/thibaultsan.com\/<\/loc>/
    end
  end
end
