defmodule PortfolioWeb.SEO.SitemapGeneratorTest do
  use Portfolio.DataCase, async: true

  alias PortfolioWeb.SEO.SitemapGenerator

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "generate_urls/1" do
    test "returns photography URLs for photo subdomain" do
      urls = SitemapGenerator.generate_urls("https://photo.thibaultsan.com")

      assert length(urls) >= 3
      assert Enum.any?(urls, fn url -> url.loc == "https://photo.thibaultsan.com" end)
      assert Enum.any?(urls, fn url -> url.loc =~ "/gallery" end)
      assert Enum.any?(urls, fn url -> url.loc =~ "/timeline" end)
    end

    test "returns AMVCC URLs for amvcc subdomain" do
      urls = SitemapGenerator.generate_urls("https://amvcc.thibaultsan.com")

      assert length(urls) == 4
      assert Enum.any?(urls, fn url -> url.loc == "https://amvcc.thibaultsan.com" end)
      assert Enum.any?(urls, fn url -> url.loc =~ "/blog" end)
    end

    test "returns tech URLs for tech subdomain" do
      urls = SitemapGenerator.generate_urls("https://tech.thibaultsan.com")

      assert length(urls) == 4
      assert Enum.any?(urls, fn url -> url.loc == "https://tech.thibaultsan.com" end)
      assert Enum.any?(urls, fn url -> url.loc =~ "/blog/ci" end)
      assert Enum.any?(urls, fn url -> url.loc =~ "/blog/kamal" end)
      assert Enum.any?(urls, fn url -> url.loc =~ "/blog/elixir" end)
    end

    test "returns static URLs for main domain" do
      urls = SitemapGenerator.generate_urls("https://thibaultsan.com")

      assert length(urls) == 1
      assert hd(urls).loc == "https://thibaultsan.com"
    end

    test "returns empty list for unknown domain" do
      urls = SitemapGenerator.generate_urls("https://example.com")

      assert urls == []
    end
  end

  describe "static_urls/1" do
    test "returns homepage for main domain" do
      urls = SitemapGenerator.static_urls("https://thibaultsan.com")

      assert length(urls) == 1
      assert hd(urls).loc == "https://thibaultsan.com"
      assert hd(urls).priority == "1.0"
      assert hd(urls).changefreq == "weekly"
    end

    test "returns empty for photo subdomain" do
      urls = SitemapGenerator.static_urls("https://photo.thibaultsan.com")
      assert urls == []
    end

    test "returns empty for non-thibaultsan domain" do
      urls = SitemapGenerator.static_urls("https://example.com")
      assert urls == []
    end
  end

  describe "photography_urls/1" do
    test "includes static photo pages" do
      urls = SitemapGenerator.photography_urls("https://photo.thibaultsan.com")

      locs = Enum.map(urls, & &1.loc)
      assert "https://photo.thibaultsan.com" in locs
      assert "https://photo.thibaultsan.com/gallery" in locs
      assert "https://photo.thibaultsan.com/timeline" in locs
    end

    test "includes hreflang alternates for main pages" do
      urls = SitemapGenerator.photography_urls("https://photo.thibaultsan.com")
      homepage = Enum.find(urls, fn url -> url.loc == "https://photo.thibaultsan.com" end)

      assert homepage.alternates != nil
      assert length(homepage.alternates) == 6

      hreflangs = Enum.map(homepage.alternates, & &1.hreflang)
      assert "fr" in hreflangs
      assert "fr-FR" in hreflangs
      assert "fr-CH" in hreflangs
      assert "en" in hreflangs
      assert "x-default" in hreflangs
    end

    test "includes published albums" do
      _album = create_album(published: true, slug: "my-album")

      urls = SitemapGenerator.photography_urls("https://photo.thibaultsan.com")

      assert Enum.any?(urls, fn url -> url.loc =~ "/my-album" end)
    end

    test "excludes unpublished albums" do
      _album = create_album(published: false, slug: "draft-album")

      urls = SitemapGenerator.photography_urls("https://photo.thibaultsan.com")

      refute Enum.any?(urls, fn url -> url.loc =~ "/draft-album" end)
    end

    test "builds photo subdomain from main URL" do
      urls = SitemapGenerator.photography_urls("https://thibaultsan.com")

      assert Enum.any?(urls, fn url -> url.loc =~ "photo.thibaultsan.com" end)
    end
  end

  describe "amvcc_urls/0" do
    test "returns AMVCC pages" do
      urls = SitemapGenerator.amvcc_urls()

      assert length(urls) == 4

      locs = Enum.map(urls, & &1.loc)
      assert "https://amvcc.thibaultsan.com" in locs
      assert "https://amvcc.thibaultsan.com/blog" in locs
      assert "https://amvcc.thibaultsan.com/blog/vetements" in locs
      assert "https://amvcc.thibaultsan.com/blog/chaussures" in locs
    end

    test "includes hreflang alternates for main pages" do
      urls = SitemapGenerator.amvcc_urls()
      homepage = Enum.find(urls, fn url -> url.loc == "https://amvcc.thibaultsan.com" end)

      assert homepage.alternates != nil
      assert length(homepage.alternates) == 5
    end

    test "has correct priorities" do
      urls = SitemapGenerator.amvcc_urls()

      homepage = Enum.find(urls, fn url -> url.loc == "https://amvcc.thibaultsan.com" end)
      assert homepage.priority == "1.0"

      blog = Enum.find(urls, fn url -> url.loc == "https://amvcc.thibaultsan.com/blog" end)
      assert blog.priority == "0.8"

      vetements =
        Enum.find(urls, fn url -> url.loc == "https://amvcc.thibaultsan.com/blog/vetements" end)

      assert vetements.priority == "0.6"
    end
  end

  describe "tech_urls/0" do
    test "returns tech blog pages" do
      urls = SitemapGenerator.tech_urls()

      assert length(urls) == 4

      locs = Enum.map(urls, & &1.loc)
      assert "https://tech.thibaultsan.com" in locs
      assert "https://tech.thibaultsan.com/blog/ci" in locs
      assert "https://tech.thibaultsan.com/blog/kamal" in locs
      assert "https://tech.thibaultsan.com/blog/elixir" in locs
    end

    test "includes hreflang alternates with Swiss priority" do
      urls = SitemapGenerator.tech_urls()
      homepage = Enum.find(urls, fn url -> url.loc == "https://tech.thibaultsan.com" end)

      assert homepage.alternates != nil

      hreflangs = Enum.map(homepage.alternates, & &1.hreflang)
      assert "fr-CH" in hreflangs
      assert "de-CH" in hreflangs
    end
  end

  describe "build_xml/1" do
    test "builds valid XML structure" do
      urls = [
        %{
          loc: "https://example.com",
          lastmod: ~D[2024-01-15],
          changefreq: "weekly",
          priority: "1.0"
        }
      ]

      xml = SitemapGenerator.build_xml(urls)

      assert xml =~ ~r/<\?xml version="1\.0" encoding="UTF-8"\?>/
      assert xml =~ ~r/<urlset xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9"/
      assert xml =~ ~r/<\/urlset>/
    end

    test "includes URL elements" do
      urls = [
        %{
          loc: "https://example.com",
          lastmod: ~D[2024-01-15],
          changefreq: "weekly",
          priority: "1.0"
        }
      ]

      xml = SitemapGenerator.build_xml(urls)

      assert xml =~ "<url>"
      assert xml =~ "<loc>https://example.com</loc>"
      assert xml =~ "<lastmod>2024-01-15</lastmod>"
      assert xml =~ "<changefreq>weekly</changefreq>"
      assert xml =~ "<priority>1.0</priority>"
    end

    test "handles empty URL list" do
      xml = SitemapGenerator.build_xml([])

      assert xml =~ "<urlset"
      assert xml =~ "</urlset>"
    end
  end

  describe "url_to_xml/1" do
    test "converts URL map to XML" do
      url = %{
        loc: "https://example.com/page",
        lastmod: ~D[2024-06-15],
        changefreq: "daily",
        priority: "0.8"
      }

      xml = SitemapGenerator.url_to_xml(url)

      assert xml =~ "<loc>https://example.com/page</loc>"
      assert xml =~ "<lastmod>2024-06-15</lastmod>"
      assert xml =~ "<changefreq>daily</changefreq>"
      assert xml =~ "<priority>0.8</priority>"
    end

    test "includes alternates when present" do
      url = %{
        loc: "https://example.com",
        lastmod: ~D[2024-01-01],
        alternates: [
          %{hreflang: "en", href: "https://example.com"},
          %{hreflang: "fr", href: "https://example.com/fr"}
        ]
      }

      xml = SitemapGenerator.url_to_xml(url)

      assert xml =~ ~s(hreflang="en")
      assert xml =~ ~s(hreflang="fr")
      assert xml =~ ~s(href="https://example.com/fr")
    end

    test "uses default values for missing fields" do
      url = %{loc: "https://example.com"}

      xml = SitemapGenerator.url_to_xml(url)

      assert xml =~ "<changefreq>weekly</changefreq>"
      assert xml =~ "<priority>0.5</priority>"
    end
  end

  describe "format_lastmod/1" do
    test "formats Date" do
      assert SitemapGenerator.format_lastmod(~D[2024-01-15]) == "2024-01-15"
    end

    test "formats DateTime" do
      datetime = ~U[2024-01-15 14:30:00Z]
      result = SitemapGenerator.format_lastmod(datetime)
      assert result =~ "2024-01-15"
    end

    test "formats NaiveDateTime" do
      naive = ~N[2024-01-15 14:30:00]
      result = SitemapGenerator.format_lastmod(naive)
      assert result =~ "2024-01-15"
    end

    test "returns today for nil" do
      result = SitemapGenerator.format_lastmod(nil)
      assert result == Date.to_iso8601(Date.utc_today())
    end

    test "returns today for invalid input" do
      result = SitemapGenerator.format_lastmod("invalid")
      assert result == Date.to_iso8601(Date.utc_today())
    end
  end
end
