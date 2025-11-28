defmodule PortfolioWeb.ImageSitemapControllerTest do
  use PortfolioWeb.ConnCase, async: true

  import PortfolioTest.Fixtures.PhotographyFixtures

  setup do
    # Clear cache before each test
    Cachex.clear(:app_cache)
    :ok
  end

  describe "GET /sitemap-images.xml" do
    test "returns XML content type", %{conn: conn} do
      conn = get(conn, ~p"/image-sitemap.xml")

      assert response_content_type(conn, :xml)
      assert response(conn, 200)
    end

    test "returns valid XML structure", %{conn: conn} do
      conn = get(conn, ~p"/image-sitemap.xml")
      body = response(conn, 200)

      assert String.starts_with?(body, ~s(<?xml version="1.0" encoding="UTF-8"?>))
      assert String.contains?(body, "<urlset")
      assert String.contains?(body, "</urlset>")
    end

    test "includes sitemap and image namespaces", %{conn: conn} do
      conn = get(conn, ~p"/image-sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, ~s(xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"))

      assert String.contains?(
               body,
               ~s(xmlns:image="http://www.google.com/schemas/sitemap-image/1.1")
             )
    end
  end

  describe "image sitemap with albums and photos" do
    setup do
      album = create_published_album(3, title: "Test Album", slug: "test-album")
      {:ok, album: album}
    end

    test "includes published albums in sitemap", %{conn: conn, album: album} do
      conn = get(conn, ~p"/image-sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, album.slug)
    end

    test "includes image elements for photos", %{conn: conn} do
      conn = get(conn, ~p"/image-sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "<image:image>")
      assert String.contains?(body, "</image:image>")
    end

    test "includes image:loc elements", %{conn: conn} do
      conn = get(conn, ~p"/image-sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "<image:loc>")
    end

    test "includes image:title elements", %{conn: conn} do
      conn = get(conn, ~p"/image-sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "<image:title>")
    end

    test "includes image:caption elements", %{conn: conn} do
      conn = get(conn, ~p"/image-sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "<image:caption>")
    end
  end

  describe "image sitemap caching" do
    test "caches sitemap content", %{conn: conn} do
      # First request generates sitemap
      conn1 = get(conn, ~p"/image-sitemap.xml")
      body1 = response(conn1, 200)

      # Second request should return cached content
      conn2 = get(build_conn(), ~p"/image-sitemap.xml")
      body2 = response(conn2, 200)

      assert body1 == body2
    end

    test "returns valid XML when cache is empty", %{conn: conn} do
      Cachex.clear(:app_cache)

      conn = get(conn, ~p"/image-sitemap.xml")
      body = response(conn, 200)

      assert String.starts_with?(body, ~s(<?xml version="1.0"))
    end
  end

  describe "image sitemap with no albums" do
    test "returns valid empty sitemap", %{conn: conn} do
      conn = get(conn, ~p"/image-sitemap.xml")
      body = response(conn, 200)

      assert String.contains?(body, "<urlset")
      assert String.contains?(body, "</urlset>")
    end
  end

  describe "XML escaping" do
    setup do
      # Create album with special characters
      album =
        create_album(
          published: true,
          title: "Test & Album <Special>",
          description: "Description with \"quotes\" and 'apostrophes'"
        )

      _photo =
        create_photo(
          album: album,
          title: "Photo & Title <Test>",
          description: "Caption with \"special\" chars"
        )

      {:ok, album: album}
    end

    test "escapes special XML characters in album content", %{conn: conn} do
      conn = get(conn, ~p"/image-sitemap.xml")
      body = response(conn, 200)

      # Should contain escaped versions
      assert String.contains?(body, "&amp;") or not String.contains?(body, " & ")
    end
  end
end
