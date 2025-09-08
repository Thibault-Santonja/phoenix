defmodule Portfolio.Photography.Events do
  @moduledoc """
  Domain events for the Photography bounded context.

  These events represent important business occurrences in the Photography domain.
  They are published when significant actions complete and allow other parts of
  the system to react without creating tight coupling.

  ## Events

  - `AlbumPublished` - An album has been published and is now visible
  - `PhotoUploaded` - A new photo has been uploaded to an album
  """

  defmodule AlbumPublished do
    @moduledoc """
    Event raised when an album is published.

    This event is triggered when an album's `published` flag is set to true,
    making it visible to the public.

    ## Fields

    - `album_id` - Unique identifier of the published album
    - `title` - Title of the album
    - `slug` - URL-friendly slug for the album
    - `published_at` - Timestamp when the album was published
    - `user_id` - ID of the user who published the album (nil for system)

    ## Use Cases

    - Send notification to subscribers
    - Update search index
    - Log analytics event
    - Trigger social media sharing
    """

    @enforce_keys [:album_id, :title, :slug, :published_at]
    defstruct [:album_id, :title, :slug, :published_at, :user_id]

    @type t :: %__MODULE__{
            album_id: Ecto.UUID.t(),
            title: String.t(),
            slug: String.t(),
            published_at: DateTime.t(),
            user_id: Ecto.UUID.t() | nil
          }
  end

  defmodule PhotoUploaded do
    @moduledoc """
    Event raised when a photo is uploaded to an album.

    This event is triggered after a photo file has been successfully
    stored and its database record created.

    ## Fields

    - `photo_id` - Unique identifier of the uploaded photo
    - `album_id` - ID of the album containing the photo
    - `file_path` - Storage path of the photo file
    - `hash` - SHA256 hash of the photo file (for integrity)
    - `uploaded_at` - Timestamp when the photo was uploaded

    ## Use Cases

    - Generate image thumbnails
    - Extract EXIF metadata
    - Run image processing pipeline
    - Update album statistics
    - Log storage metrics
    """

    @enforce_keys [:photo_id, :album_id, :file_path, :hash, :uploaded_at]
    defstruct [:photo_id, :album_id, :file_path, :hash, :uploaded_at]

    @type t :: %__MODULE__{
            photo_id: Ecto.UUID.t(),
            album_id: Ecto.UUID.t(),
            file_path: String.t(),
            hash: String.t(),
            uploaded_at: DateTime.t()
          }
  end
end
