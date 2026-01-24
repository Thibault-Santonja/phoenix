defmodule Portfolio.Photography.Storage.PhotoMetadata do
  @moduledoc """
  Metadata struct returned by storage adapters after storing a photo.

  This struct provides standardized information about a stored photo,
  including its identifier, hash, file properties, and storage location.

  ## Fields

    * `:photo_id` - Unique identifier for the photo (typically first 8 chars of hash)
    * `:hash` - Full SHA256 hash of the file content (for deduplication)
    * `:original_filename` - Original filename from the upload
    * `:content_type` - MIME type (e.g., "image/jpeg", "image/png")
    * `:file_size` - Size in bytes
    * `:storage_path` - Full path or URL where the original is stored
    * `:width` - Image width in pixels (optional)
    * `:height` - Image height in pixels (optional)
    * `:stored_at` - Timestamp when the photo was stored

  ## Example

      %PhotoMetadata{
        photo_id: "a3f2b8c4",
        hash: "a3f2b8c4f1e9d2a7c5b8d4a1e3f7c9d2",
        original_filename: "wedding-ceremony.jpg",
        content_type: "image/jpeg",
        file_size: 5_242_880,
        storage_path: "/uploads/photos/a3f2b8c4/original.jpg",
        width: 4000,
        height: 3000,
        stored_at: ~U[2024-01-15 10:30:00Z]
      }
  """

  @enforce_keys [:photo_id, :hash, :original_filename, :content_type, :file_size, :storage_path]
  defstruct [
    :photo_id,
    :hash,
    :original_filename,
    :content_type,
    :file_size,
    :storage_path,
    :width,
    :height,
    :stored_at
  ]

  @typedoc """
  Metadata returned after storing a photo.
  """
  @type t :: %__MODULE__{
          photo_id: String.t(),
          hash: String.t(),
          original_filename: String.t(),
          content_type: String.t(),
          file_size: non_neg_integer(),
          storage_path: String.t(),
          width: non_neg_integer() | nil,
          height: non_neg_integer() | nil,
          stored_at: DateTime.t() | nil
        }

  @doc """
  Create a new PhotoMetadata struct with timestamp.

  ## Examples

      iex> PhotoMetadata.new(%{
      ...>   photo_id: "a3f2b8c4",
      ...>   hash: "a3f2b8c4f1e9d2a7",
      ...>   original_filename: "photo.jpg",
      ...>   content_type: "image/jpeg",
      ...>   file_size: 1024,
      ...>   storage_path: "/uploads/photos/a3f2b8c4/original.jpg"
      ...> })
      %PhotoMetadata{...}
  """
  @spec new(map()) :: t()
  def new(attrs) do
    struct!(__MODULE__, Map.put_new(attrs, :stored_at, DateTime.utc_now()))
  end
end
