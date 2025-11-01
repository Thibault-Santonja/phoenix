defmodule Portfolio.Photography.Storage.PhotoStorage do
  @moduledoc """
  Behaviour defining the contract for photo storage adapters.

  This behaviour abstracts the storage layer for photos, allowing different
  implementations (LocalStorage, CloudflareStorage, etc.) while maintaining
  a consistent interface throughout the Photography domain.

  ## Domain Design

  The PhotoStorage behaviour follows Domain-Driven Design principles by:
  - Defining a clear contract between the domain and infrastructure layers
  - Enabling the Dependency Inversion Principle (high-level domain doesn't depend on low-level storage)
  - Supporting the Strategy pattern for pluggable storage backends

  ## Processing Status

  Note that processing status tracking (`pending`, `processing`, `completed`, `failed`)
  is handled at the Photography context level (database), not by storage adapters.
  This separation of concerns ensures that storage adapters focus solely on
  file operations, while the domain handles business logic and state management.

  ## Adapter Implementation

  Storage adapters must implement all callbacks defined in this behaviour:

      defmodule MyApp.Storage.LocalStorage do
        @behaviour Portfolio.Photography.Storage.PhotoStorage

        @impl true
        def store_photo(upload, opts) do
          # Implementation
        end

        @impl true
        def delete_photo(photo_id) do
          # Implementation
        end

        # ... other callbacks
      end

  ## Configuration

  Configure the storage adapter in your application config:

      # config/config.exs
      config :portfolio,
        photo_storage_adapter: Portfolio.Photography.Storage.LocalStorage

      # config/test.exs
      config :portfolio,
        photo_storage_adapter: Portfolio.Photography.Storage.MockStorage

  ## Usage Example

      # Get the configured adapter
      adapter = Application.get_env(:portfolio, :photo_storage_adapter)

      # Store a photo
      {:ok, metadata} = adapter.store_photo(upload, album_id: "album-123")

      # Generate variants
      {:ok, variants} = adapter.generate_variants(metadata.photo_id)

      # Get URL for a specific variant
      {:ok, url} = adapter.get_photo_url(metadata.photo_id, :thumbnail)

      # Delete photo and all variants
      :ok = adapter.delete_photo(metadata.photo_id)
  """

  alias Portfolio.Photography.Storage.PhotoMetadata

  @typedoc """
  Upload data structure from Phoenix.LiveView.

  Contains the uploaded file information including temporary path,
  client name, and content type.
  """
  @type upload :: %{
          path: String.t(),
          client_name: String.t(),
          content_type: String.t()
        }

  @typedoc """
  Options passed to storage operations.

  - `:album_id` - The album this photo belongs to (optional)
  - `:metadata` - Additional metadata to store (optional)
  """
  @type storage_opts :: [album_id: String.t(), metadata: map()]

  @typedoc """
  Variant identifier.

  Supported variants:
  - `:thumbnail` - 320px width
  - `:small` - 640px width
  - `:medium` - 1024px width
  - `:large` - 1920px width
  - `:original` - Original uploaded file
  """
  @type variant :: :thumbnail | :small | :medium | :large | :original

  @typedoc """
  Map of variant names to their file paths or URLs.

  Example:

      %{
        thumbnail: "/uploads/photos/a3f2b8c4/thumbnail.webp",
        small: "/uploads/photos/a3f2b8c4/small.webp",
        medium: "/uploads/photos/a3f2b8c4/medium.webp",
        large: "/uploads/photos/a3f2b8c4/large.webp",
        original: "/uploads/photos/a3f2b8c4/original.jpg"
      }
  """
  @type variants_map :: %{variant() => String.t()}

  @doc """
  Store the original photo file.

  This operation should:
  1. Compute a content hash (SHA256) for deduplication
  2. Store the original file in the storage backend
  3. Return metadata including photo_id, hash, file size, etc.

  The photo_id returned should be used for all subsequent operations
  (generating variants, retrieving URLs, deletion).

  ## Parameters

    * `upload` - Upload struct from Phoenix.LiveView
    * `opts` - Storage options (see `t:storage_opts/0`)

  ## Returns

    * `{:ok, metadata}` - Successfully stored, returns `PhotoMetadata`
    * `{:error, reason}` - Storage failed

  ## Examples

      iex> upload = %{path: "/tmp/photo.jpg", client_name: "vacation.jpg", content_type: "image/jpeg"}
      iex> MyStorage.store_photo(upload, album_id: "summer-2024")
      {:ok, %PhotoMetadata{
        photo_id: "a3f2b8c4",
        hash: "a3f2b8c4f1e9d2a7",
        original_filename: "vacation.jpg",
        content_type: "image/jpeg",
        file_size: 5_242_880,
        storage_path: "/uploads/photos/a3f2b8c4/original.jpg"
      }}

  ## Error Cases

    * `{:error, :disk_full}` - Not enough space
    * `{:error, :permission_denied}` - Cannot write to storage
    * `{:error, :invalid_file}` - File is corrupted or invalid format
  """
  @callback store_photo(upload(), storage_opts()) ::
              {:ok, PhotoMetadata.t()} | {:error, term()}

  @doc """
  Delete a photo and all its variants.

  This operation should:
  1. Remove the original file
  2. Remove all generated variants
  3. Clean up empty directories
  4. Be idempotent (no error if file doesn't exist)

  ## Parameters

    * `photo_id` - The photo identifier returned by `store_photo/2`

  ## Returns

    * `:ok` - Successfully deleted or already doesn't exist
    * `{:error, reason}` - Deletion failed

  ## Examples

      iex> MyStorage.delete_photo("a3f2b8c4")
      :ok

      # Idempotent - deleting twice returns :ok
      iex> MyStorage.delete_photo("a3f2b8c4")
      :ok

  ## Error Cases

    * `{:error, :permission_denied}` - Cannot delete files
  """
  @callback delete_photo(photo_id :: String.t()) :: :ok | {:error, term()}

  @doc """
  Get the public URL for a specific photo variant.

  This operation should return a URL that can be used in HTML `<img>` tags.
  For local storage, this might be a relative path like `/uploads/photos/...`.
  For cloud storage, this would be a full CDN URL.

  ## Parameters

    * `photo_id` - The photo identifier
    * `variant` - Which variant to retrieve (see `t:variant/0`)

  ## Returns

    * `{:ok, url}` - URL/path to the variant
    * `{:error, :not_found}` - Photo or variant doesn't exist
    * `{:error, reason}` - Other errors

  ## Examples

      iex> MyStorage.get_photo_url("a3f2b8c4", :thumbnail)
      {:ok, "/uploads/photos/a3f2b8c4/thumbnail.webp"}

      iex> MyStorage.get_photo_url("a3f2b8c4", :original)
      {:ok, "/uploads/photos/a3f2b8c4/original.jpg"}

      iex> MyStorage.get_photo_url("nonexistent", :thumbnail)
      {:error, :not_found}
  """
  @callback get_photo_url(photo_id :: String.t(), variant()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Generate all image variants for a photo.

  This operation should:
  1. Read the original photo
  2. Generate all configured variants (thumbnail, small, medium, large)
  3. Optimize images (WebP conversion, quality settings)
  4. Return a map of variant names to their paths/URLs

  This is typically called asynchronously by a background job worker
  after the original photo has been stored.

  ## Parameters

    * `photo_id` - The photo identifier

  ## Returns

    * `{:ok, variants_map}` - Successfully generated all variants
    * `{:error, reason}` - Generation failed

  ## Examples

      iex> MyStorage.generate_variants("a3f2b8c4")
      {:ok, %{
        thumbnail: "/uploads/photos/a3f2b8c4/thumbnail.webp",
        small: "/uploads/photos/a3f2b8c4/small.webp",
        medium: "/uploads/photos/a3f2b8c4/medium.webp",
        large: "/uploads/photos/a3f2b8c4/large.webp"
      }}

  ## Error Cases

    * `{:error, :file_not_found}` - Original photo doesn't exist
    * `{:error, :corrupted_file}` - Cannot process image
    * `{:error, :disk_full}` - Not enough space for variants
  """
  @callback generate_variants(photo_id :: String.t()) ::
              {:ok, variants_map()} | {:error, term()}

  @doc """
  Calculate total storage space used by all photos.

  This operation should:
  1. Calculate the total size of all photo files (originals + variants)
  2. Return the total size in bytes

  Used for monitoring storage usage and capacity planning.

  ## Returns

    * `non_neg_integer()` - Total storage used in bytes

  ## Examples

      iex> MyStorage.get_storage_usage()
      3_435_973_120  # ~3.2 GB
  """
  @callback get_storage_usage() :: non_neg_integer()
end
