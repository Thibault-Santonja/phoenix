defmodule Portfolio.Photography.Events do
  @moduledoc """
  Domain events for the Photography bounded context.

  These events represent important business occurrences in the Photography domain.
  They are published when significant actions complete and allow other parts of
  the system to react without creating tight coupling.

  ## Events

  - `AlbumPublished` - An album has been published and is now visible
  - `AlbumUnpublished` - An album has been unpublished and is no longer visible
  - `AlbumDeleted` - An album has been permanently deleted
  - `PhotoUploaded` - A new photo has been uploaded to an album
  - `PhotoDeleted` - A photo has been permanently deleted
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

  defmodule AlbumUnpublished do
    @moduledoc """
    Event raised when an album is unpublished.

    This event is triggered when an album's `published` flag is set to false,
    hiding it from public view.

    ## Fields

    - `album_id` - Unique identifier of the unpublished album
    - `title` - Title of the album
    - `slug` - URL-friendly slug for the album
    - `unpublished_at` - Timestamp when the album was unpublished
    - `user_id` - ID of the user who unpublished the album (nil for system)

    ## Use Cases

    - Invalidate CDN cache
    - Update search index
    - Log analytics event
    - Clear application cache
    """

    @enforce_keys [:album_id, :title, :slug, :unpublished_at]
    defstruct [:album_id, :title, :slug, :unpublished_at, :user_id]

    @type t :: %__MODULE__{
            album_id: Ecto.UUID.t(),
            title: String.t(),
            slug: String.t(),
            unpublished_at: DateTime.t(),
            user_id: Ecto.UUID.t() | nil
          }
  end

  defmodule AlbumDeleted do
    @moduledoc """
    Event raised when an album is permanently deleted.

    This event is triggered when an album and all its photos are deleted
    from the system.

    ## Fields

    - `album_id` - Unique identifier of the deleted album
    - `title` - Title of the album (for logging)
    - `slug` - URL-friendly slug for the album (for logging)
    - `deleted_at` - Timestamp when the album was deleted
    - `user_id` - ID of the user who deleted the album
    - `photo_count` - Number of photos that were deleted with the album

    ## Use Cases

    - Log audit trail
    - Update storage metrics
    - Invalidate CDN cache
    - Clear application cache
    """

    @enforce_keys [:album_id, :title, :slug, :deleted_at, :user_id, :photo_count]
    defstruct [:album_id, :title, :slug, :deleted_at, :user_id, :photo_count]

    @type t :: %__MODULE__{
            album_id: Ecto.UUID.t(),
            title: String.t(),
            slug: String.t(),
            deleted_at: DateTime.t(),
            user_id: Ecto.UUID.t(),
            photo_count: non_neg_integer()
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

  defmodule PhotoDeleted do
    @moduledoc """
    Event raised when a photo is permanently deleted.

    This event is triggered when a photo and its file are deleted
    from the system.

    ## Fields

    - `photo_id` - Unique identifier of the deleted photo
    - `album_id` - ID of the album that contained the photo
    - `file_path` - Storage path of the deleted photo file
    - `deleted_at` - Timestamp when the photo was deleted

    ## Use Cases

    - Log audit trail
    - Update storage metrics
    - Update album statistics
    - Clear thumbnail cache
    """

    @enforce_keys [:photo_id, :album_id, :file_path, :deleted_at]
    defstruct [:photo_id, :album_id, :file_path, :deleted_at]

    @type t :: %__MODULE__{
            photo_id: Ecto.UUID.t(),
            album_id: Ecto.UUID.t(),
            file_path: String.t(),
            deleted_at: DateTime.t()
          }
  end
end
