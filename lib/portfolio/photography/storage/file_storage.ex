defmodule Portfolio.Photography.Storage.FileStorage do
  @moduledoc """
  Behaviour for file storage operations.

  Abstracts file system operations from the domain layer, following Clean Architecture principles.
  This allows easy swapping between different storage backends (local, S3, etc.) without
  impacting domain logic.

  ## Implementations

  - `Portfolio.Photography.Storage.LocalStorage` - Local filesystem storage

  ## Examples

      # Store a photo
      {:ok, metadata} = storage().store_photo("wedding-2024", upload)

      # Delete a photo
      :ok = storage().delete_photo("/uploads/photo-abc123.webp")

      # Check if photo exists
      true = storage().photo_exists?("/uploads/photo-abc123.webp")
  """

  @doc """
  Stores a photo file for a given album.

  ## Parameters

    - `album_slug` - The slug of the album (used for directory structure)
    - `upload` - Map containing upload information with keys:
      - `:path` - Temporary path of the uploaded file
      - `:client_name` - Original filename from client
      - `:client_type` - MIME type of the file

  ## Returns

    - `{:ok, metadata}` where metadata contains:
      - `:file_path` - Public path to access the file
      - `:hash` - SHA256 hash of the file (for deduplication)
      - `:original_filename` - Original filename
    - `{:error, reason}` on failure

  ## Examples

      iex> upload = %{path: "/tmp/photo.jpg", client_name: "wedding.jpg", client_type: "image/jpeg"}
      iex> store_photo("mariage-2024", upload)
      {:ok, %{file_path: "/uploads/albums/mariage-2024/original/wedding-a3f2b8c4.jpg", hash: "a3f2b8c4...", original_filename: "wedding.jpg"}}
  """
  @callback store_photo(album_slug :: String.t(), upload :: map()) ::
              {:ok,
               %{
                 file_path: String.t(),
                 hash: String.t(),
                 original_filename: String.t()
               }}
              | {:error, term()}

  @doc """
  Deletes a photo file.

  ## Parameters

    - `file_path` - The path of the file to delete (as stored in database)

  ## Returns

    - `:ok` on success
    - `{:error, reason}` on failure (including :not_found if file doesn't exist)

  ## Examples

      iex> delete_photo("/uploads/albums/mariage-2024/original/wedding-a3f2b8c4.jpg")
      :ok

      iex> delete_photo("/uploads/nonexistent.jpg")
      {:error, :not_found}
  """
  @callback delete_photo(file_path :: String.t()) :: :ok | {:error, term()}

  @doc """
  Checks if a photo file exists.

  ## Parameters

    - `file_path` - The path of the file to check

  ## Returns

    - `true` if file exists
    - `false` otherwise

  ## Examples

      iex> photo_exists?("/uploads/albums/mariage-2024/original/wedding-a3f2b8c4.jpg")
      true
  """
  @callback photo_exists?(file_path :: String.t()) :: boolean()

  @doc """
  Gets the full filesystem path for a photo.

  ## Parameters

    - `file_path` - The public path of the photo

  ## Returns

    - `{:ok, full_path}` on success
    - `{:error, :not_found}` if file doesn't exist
  """
  @callback get_photo_path(file_path :: String.t()) :: {:ok, String.t()} | {:error, :not_found}
end
