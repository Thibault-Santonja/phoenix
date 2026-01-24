defmodule PortfolioWebTest do
  use PortfolioWeb.ConnCase, async: true

  describe "SEO files" do
    test "GET /robots.txt", %{conn: conn} do
      conn = get(conn, "/robots.txt")

      assert response_content_type(conn, :text)
      assert response(conn, 200) =~ "User-agent: *"
    end

    test "GET /sitemap.xml accesses the sitemap in format xml", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")

      assert response_content_type(conn, :xml)
      # The sitemap URL may or may not have a trailing slash
      assert response(conn, 200) =~ ~r/<loc>https:\/\/thibaultsan.com\/?<\/loc>/
    end
  end
end
