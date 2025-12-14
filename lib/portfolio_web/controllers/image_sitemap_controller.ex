defmodule PortfolioWeb.ImageSitemapController do
  @moduledoc """
  Controller for generating image sitemaps.

  Generates XML image sitemaps specifically for photography portfolio SEO.
  Includes all published photos with metadata for optimal Google Image Search indexing.

  Features:
  - Up to 1,000 images per sitemap (Google limit)
  - Image title, caption, and geo_location metadata
  - Geographic targeting for France, Switzerland, Belgium
  - 24-hour caching for performance

  Image sitemap format follows:
  https://developers.google.com/search/docs/crawling-indexing/sitemaps/image-sitemaps
  """

  use PortfolioWeb, :controller

  alias Portfolio.Photography

  # Cache TTL: 24 hours
  @cache_ttl 60 * 60 * 24

  # Google limit: 1000 images per sitemap
  @max_images_per_sitemap 1000

  @doc """
  Generates and serves the image sitemap.
  """
  def index(conn, _params) do
    sitemap_content = get_or_generate_image_sitemap()

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, sitemap_content)
  end

  # Private functions

  defp get_or_generate_image_sitemap do
    case Cachex.get(:portfolio_cache, :image_sitemap) do
      {:ok, nil} ->
        sitemap = generate_image_sitemap()
        _ = Cachex.put(:portfolio_cache, :image_sitemap, sitemap, ttl: :timer.seconds(@cache_ttl))
        sitemap

      {:ok, cached_sitemap} ->
        cached_sitemap

      {:error, _} ->
        generate_image_sitemap()
    end
  end

  defp generate_image_sitemap do
    photo_base = "https://photo.thibaultsan.com"

    # Get all published albums with photos
    albums = Photography.list_published_albums(preload: [:photos])

    # Build URLs with image data
    urls =
      albums
      |> Enum.map(fn album ->
        build_album_url(album, photo_base)
      end)
      |> Enum.filter(fn url -> url.images != [] end)

    build_xml(urls)
  end

  defp build_album_url(album, base_url) do
    # Only include published photos
    images =
      album.photos
      |> Enum.filter(& &1.published)
      |> Enum.take(@max_images_per_sitemap)
      |> Enum.map(fn photo ->
        build_image_data(photo, album)
      end)

    %{
      loc: "#{base_url}/#{album.slug}",
      images: images
    }
  end

  defp build_image_data(photo, album) do
    # Generate image URL - using the original file path
    image_loc = build_image_url(photo.file_path)

    # Title: Use photo title or album title + hash
    title =
      if photo.title && String.trim(photo.title) != "" do
        photo.title
      else
        "#{album.title} - #{String.slice(photo.hash, 0..7)}"
      end

    # Caption: Use photo description or album description
    caption =
      cond do
        photo.description && String.trim(photo.description) != "" ->
          photo.description

        album.description && String.trim(album.description) != "" ->
          album.description

        true ->
          title
      end

    # Geo location from EXIF data if available
    geo_location = extract_geo_location(photo.exif_data)

    %{
      loc: image_loc,
      title: title,
      caption: caption,
      geo_location: geo_location
    }
  end

  defp build_image_url(file_path) do
    # Handle both absolute URLs and relative paths
    if String.starts_with?(file_path, "http") do
      file_path
    else
      "https://thibaultsan.com#{file_path}"
    end
  end

  defp extract_geo_location(exif_data) when is_map(exif_data) do
    city = Map.get(exif_data, "City")
    state = Map.get(exif_data, "State") || Map.get(exif_data, "Province")
    country = Map.get(exif_data, "Country")

    # Build geo location string for France, Switzerland, or Belgium
    cond do
      city && country ->
        parts = [city, state, country] |> Enum.filter(& &1) |> Enum.join(", ")
        if parts != "", do: parts, else: nil

      country ->
        country

      true ->
        nil
    end
  end

  defp extract_geo_location(_), do: nil

  defp build_xml(urls) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
            xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
    #{Enum.map_join(urls, "\n", &url_to_xml/1)}
    </urlset>
    """
  end

  defp url_to_xml(url_data) do
    images_xml =
      Enum.map_join(url_data.images, "\n    ", fn image ->
        geo_tag =
          if image.geo_location do
            "\n      <image:geo_location>#{escape_xml(image.geo_location)}</image:geo_location>"
          else
            ""
          end

        """
        <image:image>
          <image:loc>#{escape_xml(image.loc)}</image:loc>
          <image:title>#{escape_xml(image.title)}</image:title>
          <image:caption>#{escape_xml(image.caption)}</image:caption>#{geo_tag}
        </image:image>
        """
        |> String.trim_trailing()
      end)

    """
      <url>
        <loc>#{url_data.loc}</loc>
    #{images_xml}
      </url>
    """
  end

  # Escape XML special characters
  defp escape_xml(nil), do: ""

  defp escape_xml(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape_xml(text), do: to_string(text)
end
