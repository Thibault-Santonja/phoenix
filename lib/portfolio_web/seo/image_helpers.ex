defmodule PortfolioWeb.SEO.ImageHelpers do
  @moduledoc """
  SEO helpers for generating semantic image alt text and metadata.

  Alt text pattern: "[Album Title] - [Photo Title or Hash]"
  Optionally includes location information from EXIF data.

  Examples:
  - "Reconstitution Napoléonienne Waterloo 2024 - La charge de la cavalerie"
  - "Fête Médiévale de Provins - photo-a3f8b2c"
  - "Reconstitution 1914-1918 - Tranchées de Verdun, Meuse, France"
  """

  @doc """
  Generates semantic alt text for a photo based on album and photo metadata.

  ## Examples

      iex> photo = %{title: "La charge", hash: "abc123def", exif_data: nil}
      iex> album = %{title: "Waterloo 2024"}
      iex> generate_alt_text(photo, album)
      "Waterloo 2024 - La charge"

      iex> photo = %{title: nil, hash: "abc123def", exif_data: nil}
      iex> album = %{title: "Waterloo 2024"}
      iex> generate_alt_text(photo, album)
      "Waterloo 2024 - photo-abc123d"
  """
  def generate_alt_text(photo, album) do
    base = build_base_alt_text(photo, album)
    location = extract_location_from_exif(photo.exif_data)

    if location do
      "#{base}, #{location}"
    else
      base
    end
  end

  @doc """
  Generates alt text for album cover/thumbnail images.

  ## Examples

      iex> album = %{title: "Reconstitution Waterloo", photo_count: 42}
      iex> generate_album_cover_alt(album)
      "Reconstitution Waterloo - 42 photos"
  """
  def generate_album_cover_alt(album) do
    count = Map.get(album, :photo_count, 0)

    if count > 0 do
      "#{album.title} - #{count} photos"
    else
      album.title
    end
  end

  # Private functions

  defp build_base_alt_text(photo, album) do
    photo_identifier =
      if has_title?(photo) do
        photo.title
      else
        "photo-#{hash_preview(photo.hash)}"
      end

    "#{album.title} - #{photo_identifier}"
  end

  defp has_title?(photo) do
    photo.title && String.trim(photo.title) != ""
  end

  defp hash_preview(hash) when is_binary(hash) do
    String.slice(hash, 0..6)
  end

  defp hash_preview(_), do: "unknown"

  defp extract_location_from_exif(exif_data) when is_map(exif_data) do
    # Try to extract location in order of specificity
    # Normalize empty strings to nil
    city = normalize_exif_value(Map.get(exif_data, "City"))
    state = normalize_exif_value(Map.get(exif_data, "State") || Map.get(exif_data, "Province"))
    country = normalize_exif_value(Map.get(exif_data, "Country"))

    build_location_string(city, state, country)
  end

  defp extract_location_from_exif(_), do: nil

  defp normalize_exif_value(nil), do: nil
  defp normalize_exif_value(""), do: nil

  defp normalize_exif_value(value) when is_binary(value),
    do: String.trim(value) |> normalize_trimmed()

  defp normalize_exif_value(_), do: nil

  defp normalize_trimmed(""), do: nil
  defp normalize_trimmed(value), do: value

  defp build_location_string(nil, nil, nil), do: nil
  defp build_location_string(city, nil, nil), do: city
  defp build_location_string(nil, state, nil), do: state
  defp build_location_string(nil, nil, country), do: country
  defp build_location_string(city, nil, country), do: "#{city}, #{country}"
  defp build_location_string(city, state, nil), do: "#{city}, #{state}"
  defp build_location_string(nil, state, country), do: "#{state}, #{country}"
  defp build_location_string(city, state, country), do: "#{city}, #{state}, #{country}"
end
