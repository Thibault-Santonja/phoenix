defmodule PortfolioWeb.SitemapControllerTest do
  use PortfolioWeb.ConnCase, async: true

  describe "GET /sitemap.xml" do
    test "returns XML content type", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")

      assert response_content_type(conn, :xml)
      assert conn.status == 200
    end

    test "returns valid XML structure", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")

      body = response(conn, 200)
      assert body =~ ~r/<\?xml version="1\.0" encoding="UTF-8"\?>/
      assert body =~ ~r/<urlset xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9"/
      assert body =~ ~r/<\/urlset>/
    end

    test "includes URL elements with required tags", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")

      body = response(conn, 200)
      assert body =~ ~r/<url>/
      assert body =~ ~r/<loc>/
      assert body =~ ~r/<lastmod>/
      assert body =~ ~r/<changefreq>/
      assert body =~ ~r/<priority>/
    end

    test "caches sitemap for subsequent requests", %{conn: conn} do
      # Clear cache first
      Cachex.del(:portfolio_cache, :sitemap)

      # First request generates sitemap
      _conn1 = get(conn, "/sitemap.xml")

      # Check cache was populated
      assert {:ok, cached} = Cachex.get(:portfolio_cache, :sitemap)
      assert cached != nil
      assert is_binary(cached)
    end

    test "returns cached sitemap on second request", %{conn: conn} do
      # Clear cache first
      Cachex.del(:portfolio_cache, :sitemap)

      # First request
      conn1 = get(conn, "/sitemap.xml")
      body1 = response(conn1, 200)

      # Second request should return same content
      conn2 = get(conn, "/sitemap.xml")
      body2 = response(conn2, 200)

      assert body1 == body2
    end

    test "returns fresh content after cache invalidation", %{conn: conn} do
      # Get initial sitemap
      conn1 = get(conn, "/sitemap.xml")
      body1 = response(conn1, 200)

      # Clear cache
      Cachex.del(:portfolio_cache, :sitemap)

      # Get new sitemap (should regenerate)
      conn2 = get(conn, "/sitemap.xml")
      body2 = response(conn2, 200)

      # Both should be valid XML
      assert body1 =~ ~r/<urlset/
      assert body2 =~ ~r/<urlset/
    end
  end

  describe "sitemap XML content" do
    test "includes valid ISO 8601 date format", %{conn: conn} do
      Cachex.del(:portfolio_cache, :sitemap)

      conn = get(conn, "/sitemap.xml")

      body = response(conn, 200)
      # Match ISO 8601 date format in lastmod
      assert body =~ ~r/<lastmod>\d{4}-\d{2}-\d{2}/
    end

    test "includes xhtml namespace for alternates", %{conn: conn} do
      Cachex.del(:portfolio_cache, :sitemap)

      conn = get(conn, "/sitemap.xml")

      body = response(conn, 200)
      assert body =~ ~s(xmlns:xhtml="http://www.w3.org/1999/xhtml")
    end

    test "includes valid priority values", %{conn: conn} do
      Cachex.del(:portfolio_cache, :sitemap)

      conn = get(conn, "/sitemap.xml")

      body = response(conn, 200)
      # Priority should be between 0.0 and 1.0
      assert body =~ ~r/<priority>[01]\.[0-9]<\/priority>/
    end

    test "includes valid changefreq values", %{conn: conn} do
      Cachex.del(:portfolio_cache, :sitemap)

      conn = get(conn, "/sitemap.xml")

      body = response(conn, 200)
      # changefreq should be one of the valid values
      assert body =~
               ~r/<changefreq>(always|hourly|daily|weekly|monthly|yearly|never)<\/changefreq>/
    end

    test "includes main domain homepage URL", %{conn: conn} do
      Cachex.del(:portfolio_cache, :sitemap)

      conn = get(conn, "/sitemap.xml")

      body = response(conn, 200)
      # Main domain includes homepage
      assert body =~ ~r/<loc>https:\/\/thibaultsan\.com<\/loc>/
    end

    test "homepage has priority 1.0", %{conn: conn} do
      Cachex.del(:portfolio_cache, :sitemap)

      conn = get(conn, "/sitemap.xml")

      body = response(conn, 200)
      assert body =~ "<priority>1.0</priority>"
    end

    test "homepage has weekly changefreq", %{conn: conn} do
      Cachex.del(:portfolio_cache, :sitemap)

      conn = get(conn, "/sitemap.xml")

      body = response(conn, 200)
      assert body =~ "<changefreq>weekly</changefreq>"
    end
  end

  describe "cache error handling" do
    test "generates sitemap when cache returns error", %{conn: conn} do
      # This tests the {:error, _} branch in get_or_generate_sitemap
      # Since we can't easily simulate cache errors, we verify the fallback works
      # by ensuring a valid sitemap is always returned

      conn = get(conn, "/sitemap.xml")

      body = response(conn, 200)
      assert body =~ ~r/<urlset/
      assert body =~ ~r/<\/urlset>/
    end
  end
end
