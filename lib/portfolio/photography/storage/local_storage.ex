defmodule Portfolio.Photography.Storage.LocalStorage do
  @moduledoc """
  Local filesystem implementation of FileStorage behaviour.

  Stores photos in `priv/static/uploads/albums/{album-slug}/original/` directory
  with filenames in format: `{slugified-name}-{hash-8chars}.{ext}`

  ## Configuration

  Reads base path from application config:

      config :portfolio, :uploads,
        base_path: "priv/static/uploads"

  ## File Organization

      priv/static/uploads/albums/
        mariage-2024/
          original/
            photo-a3f2b8c4.jpg
            dance-f1e9d2a7.jpg
        couples-session/
          original/
            portrait-c4b8a3f2.webp
  """

  @behaviour Portfolio.Photography.Storage.FileStorage

  require Logger

  # Maximum length for base filename to prevent filesystem issues
  # Keeps total filename under 255 chars (max on most filesystems)
  # Format: {base_name}-{hash}.{ext} where hash=8 chars, ext<=4 chars
  # So: 50 + 1 + 8 + 1 + 4 = 64 chars total (well under 255)
  @max_filename_length 50

  @impl true
  def store_photo(album_slug, upload) do
    with {:ok, hash} <- compute_hash(upload.path),
         {:ok, dest_path} <- build_destination_path(album_slug, upload, hash),
         :ok <- ensure_directory_exists(dest_path),
         :ok <- copy_file(upload.path, dest_path) do
      public_path = build_public_path(album_slug, upload, hash)

      {:ok,
       %{
         file_path: public_path,
         hash: hash,
         original_filename: upload.client_name
       }}
    end
  end

  @impl true
  def delete_photo(file_path) do
    full_path = build_full_path(file_path)

    if File.exists?(full_path) do
      case File.rm(full_path) do
        :ok ->
          Logger.info("Photo deleted successfully", file_path: file_path)
          :ok

        {:error, reason} ->
          Logger.error("Failed to delete photo", file_path: file_path, reason: reason)
          {:error, reason}
      end
    else
      Logger.warning("Attempted to delete non-existent photo", file_path: file_path)
      {:error, :not_found}
    end
  end

  @impl true
  def photo_exists?(file_path) do
    full_path = build_full_path(file_path)
    File.exists?(full_path)
  end

  @impl true
  def get_photo_path(file_path) do
    full_path = build_full_path(file_path)

    if File.exists?(full_path) do
      {:ok, full_path}
    else
      {:error, :not_found}
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

  @spec build_destination_path(String.t(), map(), String.t()) :: {:ok, String.t()}
  defp build_destination_path(album_slug, upload, hash) do
    base_path = Application.get_env(:portfolio, :uploads)[:base_path] || "priv/static/uploads"
    extension = get_extension(upload.client_type)
    filename = build_filename(upload.client_name, hash, extension)

    dest_path = Path.join([base_path, "albums", album_slug, "original", filename])

    {:ok, dest_path}
  end

  @spec build_public_path(String.t(), map(), String.t()) :: String.t()
  defp build_public_path(album_slug, upload, hash) do
    extension = get_extension(upload.client_type)
    filename = build_filename(upload.client_name, hash, extension)

    "/uploads/albums/#{album_slug}/original/#{filename}"
  end

  @spec build_filename(String.t(), String.t(), String.t()) :: String.t()
  defp build_filename(original_name, hash, extension) do
    # Extract base name without extension
    base_name =
      original_name
      |> Path.rootname()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9-]/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")
      |> String.slice(0, @max_filename_length)

    # Fallback to "photo" if name is empty after sanitization
    base_name = if base_name == "", do: "photo", else: base_name

    "#{base_name}-#{hash}.#{extension}"
  end

  @spec get_extension(String.t()) :: String.t()
  defp get_extension(mime_type) do
    case MIME.extensions(mime_type) do
      [ext | _] -> ext
      [] -> "jpg"
    end
  end

  @spec build_full_path(String.t()) :: String.t()
  defp build_full_path(public_path) do
    base_path = Application.get_env(:portfolio, :uploads)[:base_path] || "priv/static/uploads"

    # Remove leading "/uploads/" from public path
    relative_path = String.replace_prefix(public_path, "/uploads/", "")

    Path.join([base_path, relative_path])
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
end
