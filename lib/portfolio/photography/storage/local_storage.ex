defmodule Portfolio.Photography.Storage.LocalStorage do
  @moduledoc """
  Local filesystem implementation of PhotoStorage behaviour.

  Stores photos in hash-based structure: `priv/static/uploads/photos/{hash}/`
  This enables content-addressable storage and automatic deduplication.

  ## Configuration

  Reads base path from application config:

      config :portfolio, :uploads,
        base_path: "priv/static/uploads"

  ## File Organization

      priv/static/uploads/photos/
        a3f2b8c4/                    # Hash (SHA256, 8 chars)
          original.jpg               # Extension preserved
          thumbnail.webp
          small.webp
          medium.webp
          large.webp
        f1e9d2a7/
          original.png
          thumbnail.webp
          ...

  ## Features

  - Content-addressable storage via SHA256 hash
  - Automatic deduplication (same hash = same photo)
  - Variant generation using ImageProcessor
  - File integrity verification after storage
  """

  @behaviour Portfolio.Photography.Storage.PhotoStorage

  alias Portfolio.ImageProcessor
  alias Portfolio.Photography.Storage.PhotoMetadata

  require Logger

  @impl true
  def store_photo(upload, _opts \\ []) do
    with {:ok, hash} <- compute_hash(upload.path),
         photo_id <- String.slice(hash, 0, 8),
         {:ok, dest_path} <- build_destination_path(photo_id, upload),
         :ok <- ensure_directory_exists(dest_path),
         :ok <- copy_file(upload.path, dest_path),
         :ok <- verify_file_integrity(dest_path, hash),
         {:ok, file_stat} <- File.stat(dest_path),
         {:ok, dimensions} <- get_image_dimensions(dest_path) do
      metadata =
        PhotoMetadata.new(%{
          photo_id: photo_id,
          hash: hash,
          original_filename: upload.client_name,
          content_type: upload.content_type,
          file_size: file_stat.size,
          storage_path: build_public_path(photo_id, upload),
          width: dimensions.width,
          height: dimensions.height
        })

      {:ok, metadata}
    end
  end

  @impl true
  def delete_photo(photo_id) do
    photo_dir = build_photo_directory(photo_id)

    if File.exists?(photo_dir) do
      case File.rm_rf(photo_dir) do
        {:ok, _files} ->
          Logger.info("Photo and variants deleted successfully", photo_id: photo_id)
          :ok

        {:error, reason, _file} ->
          Logger.error("Failed to delete photo directory",
            photo_id: photo_id,
            reason: reason
          )

          {:error, reason}
      end
    else
      Logger.warning("Attempted to delete non-existent photo", photo_id: photo_id)
      :ok
    end
  end

  @impl true
  def get_photo_url(photo_id, variant) do
    photo_dir = build_photo_directory(photo_id)
    variant_filename = variant_to_filename(photo_id, variant)
    full_path = Path.join(photo_dir, variant_filename)

    if File.exists?(full_path) do
      public_path = build_variant_public_path(photo_id, variant)
      {:ok, public_path}
    else
      {:error, :not_found}
    end
  end

  @impl true
  def generate_variants(photo_id) do
    photo_dir = build_photo_directory(photo_id)
    original_path = find_original_file(photo_dir)

    case original_path do
      {:ok, source_path} ->
        case ImageProcessor.generate_variants(source_path, photo_dir) do
          {:ok, variants_map} ->
            # Convert file paths to public URLs
            public_variants =
              variants_map
              |> Enum.map(fn {variant, _path} ->
                {variant, build_variant_public_path(photo_id, variant)}
              end)
              |> Enum.into(%{})

            {:ok, public_variants}

          {:error, reason} ->
            Logger.error("Failed to generate variants",
              photo_id: photo_id,
              reason: inspect(reason)
            )

            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  @spec compute_hash(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp compute_hash(file_path) do
    hash =
      File.stream!(file_path, [], 2048)
      |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
        :crypto.hash_update(acc, chunk)
      end)
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
      |> String.slice(0, 8)

    {:ok, hash}
  rescue
    error ->
      Logger.error("Failed to compute file hash", error: inspect(error))
      {:error, :hash_computation_failed}
  end

  defp build_photo_directory(photo_id) do
    base_path = Application.get_env(:portfolio, :uploads)[:base_path] || "priv/static/uploads"
    Path.join([base_path, "photos", photo_id])
  end

  defp build_destination_path(photo_id, upload) do
    photo_dir = build_photo_directory(photo_id)
    extension = get_extension(upload.content_type)
    filename = "original.#{extension}"
    dest_path = Path.join(photo_dir, filename)

    {:ok, dest_path}
  end

  defp build_public_path(photo_id, upload) do
    extension = get_extension(upload.content_type)
    "/uploads/photos/#{photo_id}/original.#{extension}"
  end

  defp build_variant_public_path(photo_id, variant) do
    "/uploads/photos/#{photo_id}/#{variant}.webp"
  end

  defp variant_to_filename(_photo_id, :original) do
    # Will need to find the actual extension
    "original.*"
  end

  defp variant_to_filename(_photo_id, variant) do
    "#{variant}.webp"
  end

  defp find_original_file(photo_dir) do
    # Find the original file (could be .jpg, .png, .webp, etc.)
    case File.ls(photo_dir) do
      {:ok, files} ->
        original =
          Enum.find(files, fn file ->
            String.starts_with?(file, "original.")
          end)

        if original do
          {:ok, Path.join(photo_dir, original)}
        else
          Logger.error("Original file not found in directory", photo_dir: photo_dir)
          {:error, :file_not_found}
        end

      {:error, reason} ->
        Logger.error("Failed to list directory", photo_dir: photo_dir, reason: reason)
        {:error, :file_not_found}
    end
  end

  defp get_extension(mime_type) do
    case MIME.extensions(mime_type) do
      [ext | _] -> ext
      [] -> "jpg"
    end
  end

  defp get_image_dimensions(file_path) do
    case Vix.Vips.Image.new_from_file(file_path) do
      {:ok, image} ->
        width = Vix.Vips.Image.width(image)
        height = Vix.Vips.Image.height(image)
        {:ok, %{width: width, height: height}}

      {:error, _reason} ->
        # If we can't read dimensions, return nil values
        {:ok, %{width: nil, height: nil}}
    end
  end

  @spec ensure_directory_exists(String.t()) :: :ok | {:error, term()}
  defp ensure_directory_exists(file_path) do
    dir = Path.dirname(file_path)

    case File.mkdir_p(dir) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to create directory", directory: dir, reason: reason)
        {:error, :directory_creation_failed}
    end
  end

  @spec copy_file(String.t(), String.t()) :: :ok | {:error, term()}
  defp copy_file(source, destination) do
    case File.cp(source, destination) do
      :ok ->
        Logger.info("Photo stored successfully", destination: destination)
        :ok

      {:error, reason} ->
        Logger.error("Failed to copy file",
          source: source,
          destination: destination,
          reason: reason
        )

        {:error, :file_copy_failed}
    end
  end

  @spec verify_file_integrity(String.t(), String.t()) :: :ok | {:error, term()}
  defp verify_file_integrity(file_path, expected_hash) do
    case compute_hash(file_path) do
      {:ok, actual_hash} ->
        if actual_hash == expected_hash do
          :ok
        else
          Logger.error("File integrity check failed",
            file_path: file_path,
            expected_hash: expected_hash,
            actual_hash: actual_hash
          )

          # Delete corrupted file
          File.rm(file_path)
          {:error, :integrity_check_failed}
        end

      {:error, reason} ->
        Logger.error("Failed to verify file integrity", file_path: file_path, reason: reason)
        # Delete potentially corrupted file
        File.rm(file_path)
        {:error, :integrity_verification_failed}
    end
  end
end
