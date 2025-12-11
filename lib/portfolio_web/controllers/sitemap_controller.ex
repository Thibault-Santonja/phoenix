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

  alias PortfolioWeb.SEO.SitemapGenerator

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
    case Cachex.get(:portfolio_cache, :sitemap) do
      {:ok, nil} ->
        sitemap = generate_sitemap()
        _ = Cachex.put(:portfolio_cache, :sitemap, sitemap, ttl: :timer.seconds(@cache_ttl))
        sitemap

      {:ok, cached_sitemap} ->
        cached_sitemap

      {:error, _} ->
        generate_sitemap()
    end
  end

  defp generate_sitemap do
    base_url = PortfolioWeb.Endpoint.url()

    base_url
    |> SitemapGenerator.generate_urls()
    |> SitemapGenerator.build_xml()
  end
end
