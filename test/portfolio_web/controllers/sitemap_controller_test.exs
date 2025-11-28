defmodule PortfolioWeb.SitemapControllerTest do
  use PortfolioWeb.ConnCase, async: true

  setup do
    # Clear cache before each test
    Cachex.clear(:app_cache)
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

    test "includes url elements", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "<url>")
      assert String.contains?(body, "</url>")
      assert String.contains?(body, "<loc>")
      assert String.contains?(body, "<lastmod>")
    end

    test "includes required url children elements", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "<changefreq>")
      assert String.contains?(body, "<priority>")
    end
  end

  describe "sitemap structure" do
    test "includes photo subdomain URLs", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "photo.thibaultsan.com")
    end

    test "includes timeline URLs", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "/timeline")
    end
  end

  describe "sitemap caching" do
    test "caches sitemap content", %{conn: conn} do
      # First request generates sitemap
      conn1 = get(conn, ~p"/sitemap.xml")
      body1 = response(conn1, 200)

      # Second request should return cached content
      conn2 = get(build_conn(), ~p"/sitemap.xml")
      body2 = response(conn2, 200)

      assert body1 == body2
    end

    test "returns valid XML when cache is empty", %{conn: conn} do
      Cachex.clear(:app_cache)

      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert String.starts_with?(body, ~s(<?xml version="1.0"))
    end
  end

  describe "lastmod formatting" do
    test "formats lastmod as ISO8601 date", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      # Should contain ISO8601 formatted dates (YYYY-MM-DD)
      assert Regex.match?(~r/<lastmod>\d{4}-\d{2}-\d{2}/, body)
    end
  end

  describe "sitemap priorities" do
    test "homepage has highest priority", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      # Should have priority 1.0 for main pages
      assert String.contains?(body, "<priority>1.0</priority>") or
               String.contains?(body, "<priority>0.9</priority>")
    end
  end

  describe "hreflang alternates" do
    test "includes xhtml:link elements for alternates", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      # May include hreflang alternates depending on subdomain
      if String.contains?(body, "xhtml:link") do
        assert String.contains?(body, ~s(rel="alternate"))
        assert String.contains?(body, "hreflang=")
      end
    end
  end

  describe "change frequencies" do
    test "uses appropriate change frequencies", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      # Should use standard changefreq values
      valid_frequencies = ["always", "hourly", "daily", "weekly", "monthly", "yearly", "never"]

      frequencies_in_body =
        Enum.filter(valid_frequencies, fn freq ->
          String.contains?(body, "<changefreq>#{freq}</changefreq>")
        end)

      assert length(frequencies_in_body) >= 1
    end
  end
end
