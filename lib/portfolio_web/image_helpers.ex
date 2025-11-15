defmodule PortfolioWeb.ImageHelpers do
  @moduledoc """
  Helper functions for responsive image display with srcset.

  Provides utilities for generating responsive image tags that serve
  optimized variants based on screen size and device capabilities.

  ## Features

  - Automatic srcset generation from photo variants
  - WebP support with graceful fallback
  - Loading="lazy" for performance
  - Width/height attributes to prevent layout shift
  - Fallback to original during processing

  ## Usage

      # In a template
      <.responsive_image photo={@photo} alt="Photo description" />

      # With custom sizes
      <.responsive_image photo={@photo} sizes="(max-width: 768px) 100vw, 50vw" />
  """

  use Phoenix.Component

  alias Portfolio.ImageConfig
  alias Portfolio.Photography.Photo

  @doc """
  Renders a responsive image tag with srcset for optimal loading.

  Automatically generates srcset from available photo variants and falls back
  to the original image if variants are not yet processed.

  ## Attributes

  - `photo` (required) - Photo struct with variants
  - `alt` (optional) - Alt text, defaults to photo title or filename
  - `class` (optional) - CSS classes to apply
  - `sizes` (optional) - Sizes attribute for responsive images
  - `loading` (optional) - Loading strategy (lazy/eager), defaults to "lazy"

  ## Examples

      <.responsive_image photo={@photo} />

      <.responsive_image
        photo={@photo}
        alt="Beautiful sunset"
        class="rounded-lg shadow-md"
        sizes="(max-width: 640px) 100vw, (max-width: 1024px) 80vw, 1024px"
      />
  """
  attr :photo, Photo, required: true
  attr :alt, :string, default: nil
  attr :class, :string, default: ""
  attr :sizes, :string, default: "(max-width: 640px) 100vw, (max-width: 1024px) 80vw, 1024px"
  attr :loading, :string, default: "lazy"
  attr :rest, :global

  def responsive_image(assigns) do
    assigns = assign(assigns, :dimensions, extract_dimensions(assigns.photo))

    ~H"""
    <%= if @photo.processing_status == "completed" && map_size(@photo.variants) > 0 do %>
      <img
        src={get_default_src(@photo)}
        srcset={image_srcset(@photo)}
        sizes={@sizes}
        alt={@alt || @photo.title || @photo.original_filename}
        width={@dimensions.width}
        height={@dimensions.height}
        class={@class}
        loading={@loading}
        decoding="async"
        {@rest}
      />
    <% else %>
      <%!-- Fallback to original while processing or if variants not available --%>
      <img
        src={@photo.file_path}
        alt={@alt || @photo.title || @photo.original_filename}
        width={@dimensions.width}
        height={@dimensions.height}
        class={@class}
        loading={@loading}
        decoding="async"
        {@rest}
      />
    <% end %>
    """
  end

  @doc """
  Generates srcset attribute value from photo variants.

  Creates a comma-separated list of image URLs with their respective widths
  for the browser to choose the optimal image.

  ## Examples

      iex> photo = %Photo{variants: %{
      ...>   "thumbnail" => "/photos/abc/thumbnail.webp",
      ...>   "small" => "/photos/abc/small.webp",
      ...>   "medium" => "/photos/abc/medium.webp",
      ...>   "large" => "/photos/abc/large.webp"
      ...> }}
      iex> ImageHelpers.image_srcset(photo)
      "/photos/abc/thumbnail.webp 320w, /photos/abc/small.webp 640w, /photos/abc/medium.webp 1024w, /photos/abc/large.webp 1920w"
  """
  @spec image_srcset(Photo.t()) :: String.t()
  def image_srcset(%Photo{variants: variants}) when is_map(variants) do
    # Get variant widths from centralized configuration
    variant_widths = ImageConfig.variant_widths()

    variants
    |> Enum.filter(fn {name, _url} -> Map.has_key?(variant_widths, name) end)
    |> Enum.sort_by(fn {name, _url} -> variant_widths[name] end)
    |> Enum.map_join(", ", fn {name, url} ->
      width = variant_widths[name]
      "#{url} #{width}w"
    end)
  end

  def image_srcset(_photo), do: ""

  @doc """
  Returns the default src URL for an image.

  Prefers the medium variant as the default fallback, or the first available
  variant if medium is not available.

  ## Examples

      iex> photo = %Photo{variants: %{"medium" => "/photos/abc/medium.webp"}}
      iex> ImageHelpers.get_default_src(photo)
      "/photos/abc/medium.webp"
  """
  @spec get_default_src(Photo.t()) :: String.t()
  def get_default_src(%Photo{variants: variants, file_path: file_path})
      when is_map(variants) and map_size(variants) > 0 do
    # Prefer medium as default, fallback to first available variant
    variants["medium"] || variants["small"] || variants["large"] || variants["thumbnail"] ||
      file_path
  end

  def get_default_src(%Photo{file_path: file_path}), do: file_path

  @doc """
  Returns a thumbnail URL for the photo.

  ## Examples

      iex> photo = %Photo{variants: %{"thumbnail" => "/photos/abc/thumbnail.webp"}}
      iex> ImageHelpers.thumbnail_url(photo)
      "/photos/abc/thumbnail.webp"
  """
  @spec thumbnail_url(Photo.t()) :: String.t()
  def thumbnail_url(%Photo{variants: variants, file_path: file_path})
      when is_map(variants) and map_size(variants) > 0 do
    variants["thumbnail"] || variants["small"] || file_path
  end

  def thumbnail_url(%Photo{file_path: file_path}), do: file_path

  @doc """
  Extracts image dimensions from EXIF data or provides default values.

  Returns a map with width and height keys. Attempts to extract dimensions
  from EXIF data first, falls back to variant configuration, or returns nil
  to allow browser to determine dimensions.

  ## Examples

      iex> photo = %Photo{exif_data: %{"ImageWidth" => 1920, "ImageHeight" => 1080}}
      iex> ImageHelpers.extract_dimensions(photo)
      %{width: 1920, height: 1080}

      iex> photo = %Photo{exif_data: %{}}
      iex> ImageHelpers.extract_dimensions(photo)
      %{width: nil, height: nil}
  """
  @spec extract_dimensions(Photo.t()) :: %{width: integer() | nil, height: integer() | nil}
  def extract_dimensions(%Photo{exif_data: exif_data}) when is_map(exif_data) do
    width = exif_data["ImageWidth"] || exif_data["PixelWidth"] || exif_data["ExifImageWidth"]
    height = exif_data["ImageHeight"] || exif_data["PixelHeight"] || exif_data["ExifImageHeight"]

    %{
      width: parse_dimension(width),
      height: parse_dimension(height)
    }
  end

  def extract_dimensions(_photo), do: %{width: nil, height: nil}

  # Parse dimension value to integer, handling various formats
  defp parse_dimension(value) when is_integer(value), do: value
  defp parse_dimension(value) when is_binary(value), do: String.to_integer(value)
  defp parse_dimension(_), do: nil
end
