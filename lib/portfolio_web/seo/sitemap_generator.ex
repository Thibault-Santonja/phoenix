defmodule PortfolioWeb.SEO.SitemapGenerator do
  @moduledoc """
  Generates sitemap URLs for different subdomains.

  This module contains pure functions for generating sitemap content,
  extracted from SitemapController for better testability.
  """

  alias Portfolio.Photography

  @doc """
  Generates sitemap URLs based on the base URL (subdomain detection).

  ## Examples

      iex> generate_urls("https://photo.thibaultsan.com")
      [%{loc: "https://photo.thibaultsan.com", ...}, ...]

      iex> generate_urls("https://thibaultsan.com")
      [%{loc: "https://thibaultsan.com", ...}]
  """
  @spec generate_urls(String.t()) :: [map()]
  def generate_urls(base_url) do
    cond do
      String.contains?(base_url, "photo.") ->
        photography_urls(base_url)

      String.contains?(base_url, "amvcc.") ->
        amvcc_urls()

      String.contains?(base_url, "tech.") ->
        tech_urls()

      true ->
        static_urls(base_url)
    end
  end

  @doc """
  Builds XML sitemap from a list of URL maps.
  """
  @spec build_xml([map()]) :: String.t()
  def build_xml(urls) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
            xmlns:xhtml="http://www.w3.org/1999/xhtml">
    #{Enum.map_join(urls, "\n", &url_to_xml/1)}
    </urlset>
    """
  end

  @doc """
  Generates URLs for the main domain (homepage only).
  """
  def static_urls(base_url) do
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
      []
    end
  end

  @doc """
  Generates URLs for the photography subdomain.
  """
  @spec photography_urls(String.t()) :: [map()]
  def photography_urls(base_url) do
    photo_base =
      if String.contains?(base_url, "photo.") do
        base_url
      else
        String.replace(base_url, "://", "://photo.")
      end

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

  @doc """
  Generates URLs for the AMVCC subdomain.
  """
  def amvcc_urls do
    amvcc_base = "https://amvcc.thibaultsan.com"

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

  @doc """
  Generates URLs for the tech subdomain.
  """
  def tech_urls do
    tech_base = "https://tech.thibaultsan.com"

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

  @doc """
  Converts a URL map to XML string.
  """
  @spec url_to_xml(map()) :: String.t()
  def url_to_xml(url_data) do
    lastmod = format_lastmod(url_data[:lastmod])

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

  @doc """
  Formats a lastmod value to ISO8601 string.
  """
  @spec format_lastmod(Date.t() | DateTime.t() | NaiveDateTime.t() | nil) :: String.t()
  def format_lastmod(%Date{} = date), do: Date.to_iso8601(date)
  def format_lastmod(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  def format_lastmod(%NaiveDateTime{} = naive), do: NaiveDateTime.to_iso8601(naive)
  def format_lastmod(_), do: Date.to_iso8601(Date.utc_today())
end
