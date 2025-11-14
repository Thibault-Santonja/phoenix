defmodule PortfolioTest.Fixtures.PhotographyFixtures do
  @moduledoc """
  Test fixtures for the Photography context.

  These helpers use the application's public API to ensure generated
  data respects business rules and constraints.

  See docs/guides/generating-data-functions.md for more information.
  """

  alias Portfolio.Photography

  @doc """
  Creates an album through the Photography context API.

  This ensures the album is created with proper validations,
  including slug generation and date validation.

  ## Options

    * `:title` - Album title (generates unique title if not provided)
    * `:type` - Album type (defaults to :wedding)
    * `:date_prise_vue` - Date of photo shoot (defaults to today)
    * `:location` - Location of the shoot (optional)
    * `:description` - Album description (optional)
    * `:published` - Whether album is published (defaults to false)
    * `:reference_link` - External reference link (optional)

  ## Examples

      iex> album = create_album()
      iex> album.type
      :wedding

      iex> album = create_album(title: "My Wedding", published: true)
      iex> album.published
      true
  """
  def create_album(attrs \\ []) do
    title =
      Keyword.get_lazy(attrs, :title, fn ->
        "Album #{System.unique_integer([:positive])}"
      end)

    type = Keyword.get(attrs, :type, :wedding)
    date_prise_vue = Keyword.get(attrs, :date_prise_vue, Date.utc_today())
    date_fin_prise_vue = Keyword.get(attrs, :date_fin_prise_vue)
    location = Keyword.get(attrs, :location)
    description = Keyword.get(attrs, :description)
    published = Keyword.get(attrs, :published, false)
    reference_link = Keyword.get(attrs, :reference_link)
    slug = Keyword.get(attrs, :slug)

    params =
      %{
        title: title,
        type: type,
        date_prise_vue: date_prise_vue,
        published: published
      }
      |> maybe_add(:date_fin_prise_vue, date_fin_prise_vue)
      |> maybe_add(:location, location)
      |> maybe_add(:description, description)
      |> maybe_add(:reference_link, reference_link)
      |> maybe_add(:slug, slug)

    {:ok, album} = Photography.create_album(params)
    album
  end

  @doc """
  Creates a photo through the Photography context API.

  This ensures the photo is created with proper validations
  and is associated with an album.

  ## Options

    * `:album` - Album to add photo to (creates new album if not provided)
    * `:file_path` - Path to the photo file (required)
    * `:original_filename` - Original filename (required)
    * `:title` - Photo title (optional)
    * `:description` - Photo description (optional)
    * `:display_order` - Display order in album (defaults to 0)
    * `:taken_at` - Date photo was taken (optional)
    * `:published` - Whether photo is published (defaults to true)
    * `:processing_status` - Processing status (defaults to "pending")
    * `:variants` - Map of variant URLs (optional)

  ## Examples

      iex> album = create_album()
      iex> photo = create_photo(album: album, file_path: "/uploads/test.jpg")
      iex> photo.album_id == album.id
      true
  """
  def create_photo(attrs \\ []) do
    album = Keyword.get_lazy(attrs, :album, &create_album/0)

    file_path =
      Keyword.get_lazy(attrs, :file_path, fn ->
        "/uploads/photo-#{System.unique_integer([:positive])}.jpg"
      end)

    original_filename =
      Keyword.get_lazy(attrs, :original_filename, fn ->
        "photo-#{System.unique_integer([:positive])}.jpg"
      end)

    title = Keyword.get(attrs, :title)
    description = Keyword.get(attrs, :description)
    display_order = Keyword.get(attrs, :display_order, 0)
    taken_at = Keyword.get(attrs, :taken_at)
    published = Keyword.get(attrs, :published, true)
    processing_status = Keyword.get(attrs, :processing_status, "pending")
    variants = Keyword.get(attrs, :variants)

    params =
      %{
        album_id: album.id,
        file_path: file_path,
        original_filename: original_filename,
        display_order: display_order,
        published: published,
        processing_status: processing_status
      }
      |> maybe_add(:title, title)
      |> maybe_add(:description, description)
      |> maybe_add(:taken_at, taken_at)
      |> maybe_add(:variants, variants)

    {:ok, photo} = Photography.create_photo(params)
    photo
  end

  @doc """
  Creates an album with a specified number of photos.

  This is a convenience helper for tests that need an album
  with multiple photos already populated.

  ## Options

  First argument is the number of photos to create (default: 3).
  Second argument accepts all options from `create_album/1`.

  ## Examples

      iex> album = create_album_with_photos(5)
      iex> length(album.photos)
      5

      iex> album = create_album_with_photos(3, title: "Wedding Album", published: true)
      iex> album.published
      true
  """
  def create_album_with_photos(photo_count \\ 3, attrs \\ []) do
    album = create_album(attrs)

    _photos =
      for i <- 1..photo_count do
        create_photo(
          album: album,
          file_path: "/uploads/photo_#{i}.jpg",
          original_filename: "photo_#{i}.jpg",
          display_order: i - 1
        )
      end

    # Reload album with photos preloaded
    Photography.get_album!(album.id, preload: [:photos])
  end

  @doc """
  Creates a published album ready to appear on the timeline.

  This is a convenience helper that creates an album with photos
  and sets it as published, simulating what would appear publicly.

  ## Options

  Same as `create_album_with_photos/2`, but `published` defaults to true.

  ## Examples

      iex> album = create_published_album(3, title: "Summer Wedding")
      iex> album.published
      true
      iex> length(album.photos)
      3
  """
  def create_published_album(photo_count \\ 3, attrs \\ []) do
    attrs = Keyword.put_new(attrs, :published, true)
    create_album_with_photos(photo_count, attrs)
  end

  @doc """
  Creates multiple albums for testing list views.

  This generates albums with different types and dates,
  useful for testing sorting, filtering, and grouping.

  ## Options

    * `:count` - Number of albums to create (default: 3)
    * `:published` - Whether albums should be published (default: false)
    * `:with_photos` - Number of photos per album (default: 0)

  ## Examples

      iex> albums = create_albums(count: 5, published: true, with_photos: 2)
      iex> length(albums)
      5
  """
  def create_albums(attrs \\ []) do
    count = Keyword.get(attrs, :count, 3)
    published = Keyword.get(attrs, :published, false)
    with_photos = Keyword.get(attrs, :with_photos, 0)

    album_types = [:wedding, :couples, :motherhood, :landscape, :music]

    for i <- 1..count do
      album_type = Enum.at(album_types, rem(i, length(album_types)))

      date = Date.add(Date.utc_today(), -i * 30)

      album_attrs = [
        title: "Album #{i}",
        type: album_type,
        date_prise_vue: date,
        published: published
      ]

      if with_photos > 0 do
        create_album_with_photos(with_photos, album_attrs)
      else
        create_album(album_attrs)
      end
    end
  end

  # Private helpers

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
