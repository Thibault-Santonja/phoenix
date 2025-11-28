defmodule PortfolioWeb.SitemapController do
  @moduledoc """
  Controller for generating dynamic sitemaps.

  Generates XML sitemaps for SEO optimization including:
  - Static pages (homepage, main sections)
  - Dynamic photography albums
  - Blog posts
  - Multi-language support (fr-FR, fr-CH, fr-BE, en)

  The sitemap is cached for 24 hours to optimize performance.
  """

  use PortfolioWeb, :controller

  alias Portfolio.Photography

  # Cache TTL: 24 hours
  @cache_ttl 60 * 60 * 24

  @doc """
  Generates and serves the main sitemap.xml file.
  """
  def index(conn, _params) do
    sitemap_content = get_or_generate_sitemap()

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, sitemap_content)
  end

  # Private functions

  defp get_or_generate_sitemap do
    case Cachex.get(:app_cache, :sitemap) do
      {:ok, nil} ->
        sitemap = generate_sitemap()
        _ = Cachex.put(:app_cache, :sitemap, sitemap, ttl: :timer.seconds(@cache_ttl))
        sitemap

      {:ok, cached_sitemap} ->
        cached_sitemap

      {:error, _} ->
        generate_sitemap()
    end
  end

  defp generate_sitemap do
    base_url = PortfolioWeb.Endpoint.url()

    # Only include relevant URLs based on subdomain
    urls =
      cond do
        String.contains?(base_url, "photo.") ->
          # Photo subdomain: only photography content
          photography_urls(base_url)

        String.contains?(base_url, "amvcc.") ->
          # AMVCC subdomain: only AMVCC content
          amvcc_urls()

        String.contains?(base_url, "tech.") ->
          # Tech subdomain: only tech blog content
          tech_urls()

        true ->
          # Main domain: homepage only
          static_urls(base_url)
      end

    build_xml(urls)
  end

  defp static_urls(base_url) do
    # Main homepage - simple, points to subdomains
    if String.contains?(base_url, "thibaultsan.com") and
         not String.contains?(base_url, "photo.") and
         not String.contains?(base_url, "amvcc.") and
         not String.contains?(base_url, "tech.") do
      [
        %{
          loc: base_url,
          lastmod: Date.utc_today(),
          changefreq: "weekly",
          priority: "1.0"
        }
      ]
    else
      # Other subdomains don't have static pages in sitemap
      []
    end
  end

  defp photography_urls(base_url) do
    # For photo subdomain, use current URL. Otherwise, build photo subdomain URL
    photo_base =
      if String.contains?(base_url, "photo.") do
        base_url
      else
        String.replace(base_url, "://", "://photo.")
      end

    # Hreflang alternates for France, Switzerland, Belgium targeting
    photo_alternates = [
      %{hreflang: "fr", href: photo_base},
      %{hreflang: "fr-FR", href: photo_base},
      %{hreflang: "fr-CH", href: photo_base},
      %{hreflang: "fr-BE", href: photo_base},
      %{hreflang: "en", href: photo_base},
      %{hreflang: "x-default", href: photo_base}
    ]

    static_photo_urls = [
      %{
        loc: photo_base,
        lastmod: Date.utc_today(),
        changefreq: "weekly",
        priority: "1.0",
        alternates: photo_alternates
      },
      %{
        loc: "#{photo_base}/gallery",
        lastmod: Date.utc_today(),
        changefreq: "daily",
        priority: "0.9",
        alternates: photo_alternates
      },
      %{
        loc: "#{photo_base}/timeline",
        lastmod: Date.utc_today(),
        changefreq: "daily",
        priority: "0.8",
        alternates: photo_alternates
      }
    ]

    # Add dynamic album pages
    album_urls =
      Photography.list_published_albums()
      |> Enum.map(fn album ->
        %{
          loc: "#{photo_base}/#{album.slug}",
          lastmod: album.updated_at || album.inserted_at,
          changefreq: "weekly",
          priority: "0.8"
        }
      end)

    static_photo_urls ++ album_urls
  end

  defp amvcc_urls do
    amvcc_base = "https://amvcc.thibaultsan.com"

    # Hreflang for France-focused (Picardy), Belgium, Switzerland
    amvcc_alternates = [
      %{hreflang: "fr", href: amvcc_base},
      %{hreflang: "fr-FR", href: amvcc_base},
      %{hreflang: "fr-BE", href: amvcc_base},
      %{hreflang: "fr-CH", href: amvcc_base},
      %{hreflang: "x-default", href: amvcc_base}
    ]

    [
      %{
        loc: amvcc_base,
        lastmod: Date.utc_today(),
        changefreq: "weekly",
        priority: "1.0",
        alternates: amvcc_alternates
      },
      %{
        loc: "#{amvcc_base}/blog",
        lastmod: Date.utc_today(),
        changefreq: "monthly",
        priority: "0.8",
        alternates: amvcc_alternates
      },
      %{
        loc: "#{amvcc_base}/blog/vetements",
        lastmod: Date.utc_today(),
        changefreq: "monthly",
        priority: "0.6"
      },
      %{
        loc: "#{amvcc_base}/blog/chaussures",
        lastmod: Date.utc_today(),
        changefreq: "monthly",
        priority: "0.6"
      }
    ]
  end

  defp tech_urls do
    tech_base = "https://tech.thibaultsan.com"

    # Hreflang for tech: Geneva > Paris > Switzerland > France > Europe
    # Priority: fr-CH (Geneva) > fr-FR (Paris) > en (international)
    tech_alternates = [
      %{hreflang: "fr-CH", href: tech_base},
      %{hreflang: "fr", href: tech_base},
      %{hreflang: "fr-FR", href: tech_base},
      %{hreflang: "en", href: tech_base},
      %{hreflang: "de-CH", href: tech_base},
      %{hreflang: "x-default", href: tech_base}
    ]

    [
      %{
        loc: tech_base,
        lastmod: Date.utc_today(),
        changefreq: "weekly",
        priority: "1.0",
        alternates: tech_alternates
      },
      %{
        loc: "#{tech_base}/blog/ci",
        lastmod: Date.utc_today(),
        changefreq: "monthly",
        priority: "0.8",
        alternates: tech_alternates
      },
      %{
        loc: "#{tech_base}/blog/kamal",
        lastmod: Date.utc_today(),
        changefreq: "monthly",
        priority: "0.8",
        alternates: tech_alternates
      },
      %{
        loc: "#{tech_base}/blog/elixir",
        lastmod: Date.utc_today(),
        changefreq: "monthly",
        priority: "0.8",
        alternates: tech_alternates
      }
    ]
  end

  defp build_xml(urls) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
            xmlns:xhtml="http://www.w3.org/1999/xhtml">
    #{Enum.map_join(urls, "\n", &url_to_xml/1)}
    </urlset>
    """
  end

  defp url_to_xml(url_data) do
    lastmod =
      case url_data[:lastmod] do
        %Date{} = date -> Date.to_iso8601(date)
        %DateTime{} = datetime -> DateTime.to_iso8601(datetime)
        %NaiveDateTime{} = naive -> NaiveDateTime.to_iso8601(naive)
        _ -> Date.to_iso8601(Date.utc_today())
      end

    alternates_xml =
      if url_data[:alternates] do
        Enum.map_join(url_data[:alternates], "\n    ", fn alt ->
          ~s(<xhtml:link rel="alternate" hreflang="#{alt.hreflang}" href="#{alt.href}" />)
        end)
      else
        ""
      end

    """
      <url>
        <loc>#{url_data.loc}</loc>
        <lastmod>#{lastmod}</lastmod>
        <changefreq>#{url_data[:changefreq] || "weekly"}</changefreq>
        <priority>#{url_data[:priority] || "0.5"}</priority>
    #{alternates_xml}
      </url>
    """
  end
end
