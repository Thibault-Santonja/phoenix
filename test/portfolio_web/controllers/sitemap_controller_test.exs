defmodule PortfolioWeb.SitemapControllerTest do
  use PortfolioWeb.ConnCase, async: false

  setup do
    # Clear cache before each test
    Cachex.clear(:portfolio_cache)
    :ok
  end

  describe "GET /sitemap.xml" do
    test "returns XML content type", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")

      assert response_content_type(conn, :xml)
      assert response(conn, 200)
    end

    test "returns valid XML structure", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.starts_with?(body, ~s(<?xml version="1.0" encoding="UTF-8"?>))
      assert String.contains?(body, "<urlset")
      assert String.contains?(body, "</urlset>")
    end

    test "includes sitemap namespace", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, ~s(xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"))
    end

    test "includes xhtml namespace for alternates", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, ~s(xmlns:xhtml="http://www.w3.org/1999/xhtml"))
    end
  end

  describe "main domain sitemap (thibaultsan.com)" do
    # Test config sets host to thibaultsan.com

    test "includes homepage URL", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "<loc>https://thibaultsan.com</loc>")
    end

    test "includes url elements with required children", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "<url>")
      assert String.contains?(body, "</url>")
      assert String.contains?(body, "<loc>")
      assert String.contains?(body, "<lastmod>")
      assert String.contains?(body, "<changefreq>")
      assert String.contains?(body, "<priority>")
    end

    test "formats lastmod as ISO8601 date", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      # Should contain ISO8601 formatted dates (YYYY-MM-DD)
      assert Regex.match?(~r/<lastmod>\d{4}-\d{2}-\d{2}/, body)
    end

    test "homepage has highest priority", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "<priority>1.0</priority>")
    end

    test "uses weekly change frequency for homepage", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "<changefreq>weekly</changefreq>")
    end
  end

  describe "sitemap caching" do
    test "caches sitemap content", %{conn: conn} do
      Cachex.clear(:portfolio_cache)

      # First request generates sitemap
      conn1 = get(conn, ~p"/sitemap.xml")
      body1 = response(conn1, 200)

      # Second request should return cached content
      conn2 = get(build_conn(), ~p"/sitemap.xml")
      body2 = response(conn2, 200)

      assert body1 == body2
    end

    test "returns valid XML when cache is empty", %{conn: conn} do
      Cachex.clear(:portfolio_cache)

      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.starts_with?(body, ~s(<?xml version="1.0"))
    end

    test "stores sitemap in cache after generation", %{conn: conn} do
      Cachex.clear(:portfolio_cache)

      # Generate sitemap
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      # Check cache contains the sitemap
      {:ok, cached} = Cachex.get(:portfolio_cache, :sitemap)
      assert cached == body
    end
  end

  describe "XML structure validation" do
    test "generates well-formed XML", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      # Check basic XML structure
      assert String.starts_with?(body, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      assert String.contains?(body, "<urlset")
      assert String.contains?(body, "</urlset>")

      # Each <url> should be properly closed
      url_count = length(Regex.scan(~r/<url>/, body))
      url_close_count = length(Regex.scan(~r/<\/url>/, body))
      assert url_count == url_close_count
    end

    test "all loc elements are properly closed", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      loc_count = length(Regex.scan(~r/<loc>/, body))
      loc_close_count = length(Regex.scan(~r/<\/loc>/, body))
      assert loc_count == loc_close_count
    end
  end

  describe "cache error handling" do
    test "handles cache miss gracefully", %{conn: conn} do
      # Ensure cache is empty
      Cachex.clear(:portfolio_cache)

      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.starts_with?(body, "<?xml")
      assert String.contains?(body, "thibaultsan.com")
    end
  end
end
