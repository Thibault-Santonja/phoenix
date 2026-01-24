defmodule Portfolio.Photography.Services.PhotoUploadService do
  @moduledoc """
  Service for uploading photos with parallel processing.

  Responsibilities:
  - Parallel file upload using Task.async_stream
  - Error handling and recovery
  - Telemetry tracking
  - Storage abstraction

  This service encapsulates the complex workflow of uploading multiple photos
  in parallel, handling errors, timeouts, and tracking performance metrics.

  ## Error Types

  The service can return the following error types:

  | Error | Description |
  |-------|-------------|
  | `:album_not_found` | The target album does not exist |
  | `:partial_upload_failure` | Some files uploaded, but at least one failed. All uploaded files are rolled back. |
  | `{:file_too_large, filename, size, max_size}` | A file exceeds the maximum allowed size |
  | `{:file_error, filename, reason}` | File system error (e.g., file not found, permission denied) |
  | `%Ecto.Changeset{}` | Database validation error when creating photo records |

  ## Upload Workflow

  1. Validate album exists
  2. Pre-validate all file sizes (fail fast before any I/O)
  3. Upload files in parallel to storage
  4. Create photo records atomically in database
  5. On any failure: rollback uploaded files (best-effort)

  ## Telemetry Events

  Emits `[:portfolio, :photography, :photos, :uploaded]` with:
  - `album_slug` - Target album slug
  - `count` - Number of photos uploaded
  """

  use Portfolio.Service

  alias Ecto.Multi
  alias Portfolio.Photography
  alias Portfolio.Repo

  require Logger

  # Type definitions for better documentation and dialyzer support

  @typedoc "Photo metadata returned after successful upload"
  @type photo_metadata :: %{
          file_path: String.t(),
          storage_path: String.t(),
          hash: String.t(),
          original_filename: String.t(),
          photo_id: String.t()
        }

  @typedoc "Error reasons that can be returned by execute/3"
  @type error_reason ::
          :album_not_found
          | :partial_upload_failure
          | {:file_too_large, filename :: String.t(), size :: pos_integer(),
             max_size :: pos_integer()}
          | {:file_error, filename :: String.t(), reason :: atom()}
          | Ecto.Changeset.t()

  @typedoc "Upload entry from Phoenix.LiveView.Upload or similar"
  @type upload :: %{
          required(:path) => String.t(),
          required(:client_name) => String.t(),
          optional(atom()) => term()
        }

  @impl true
  @doc """
  Uploads multiple photos in parallel to an album.

  ## Parameters

  - `album_slug` - Slug of the target album
  - `uploads` - List of upload maps (from Phoenix.LiveView.Upload or similar)
  - `opts` - Options
    - `:max_concurrency` - Maximum parallel uploads (default: 4)
    - `:timeout` - Timeout per upload in ms (default: 30000)
    - `:ordered` - Whether to preserve order (default: false)

  ## Returns

  - `{:ok, metadata_list}` - List of uploaded photo metadata
  - `{:error, reason}` - Upload failed (see module doc for error types)

  ## Examples

      iex> execute("wedding-2024", [upload1, upload2], max_concurrency: 8)
      {:ok, [%{file_path: "...", hash: "..."}, ...]}

      iex> execute("invalid-album", [upload])
      {:error, :album_not_found}

      iex> execute("album", [large_file])
      {:error, {:file_too_large, "photo.jpg", 52_428_800, 10_485_760}}
  """
  @spec execute(String.t(), [upload()], keyword()) ::
          {:ok, [photo_metadata()]} | {:error, error_reason()}
  def execute(album_slug, uploads, opts \\ []) when is_list(uploads) do
    count = length(uploads)

    with_telemetry(
      [:portfolio, :photography, :photos, :uploaded],
      %{album_slug: album_slug, count: count},
      fn ->
        # Step 1: Get album
        with {:ok, album} <- Photography.get_album_by_slug(album_slug),
             # Step 2: Upload files in parallel (no DB yet)
             {:ok, photos_metadata} <- upload_files_parallel(album_slug, uploads, opts),
             # Step 3: Create photos in DB atomically with Ecto.Multi
             {:ok, _photos} <- create_photos_atomically(album, photos_metadata) do
          {:ok, photos_metadata}
        else
          {:error, :upload_failed, _failed_reason, uploaded_metadata} ->
            # Rollback: delete successfully uploaded files
            rollback_uploaded_files(uploaded_metadata)
            {:error, :partial_upload_failure}

          {:error, reason} ->
            {:error, reason}
        end
      end
    )
  end

  # Upload files in parallel without creating DB records yet
  defp upload_files_parallel(_album_slug, uploads, opts) do
    max_size = get_max_file_size()

    # Pre-validate file sizes before any I/O
    case validate_upload_sizes(uploads, max_size) do
      :ok ->
        do_upload_files_parallel(uploads, opts)

      {:error, {filename, size}} when is_binary(filename) and is_integer(size) ->
        {:error, {:file_too_large, filename, size, max_size}}

      {:error, {filename, reason}} when is_binary(filename) and is_atom(reason) ->
        {:error, {:file_error, filename, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_upload_files_parallel(uploads, opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 4)
    timeout = Keyword.get(opts, :timeout, 30_000)
    ordered = Keyword.get(opts, :ordered, false)

    results =
      uploads
      |> Task.async_stream(
        fn upload -> storage().store_photo(upload, []) end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        ordered: ordered,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    # Separate successes from failures
    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

    uploaded_metadata = Enum.map(successes, fn {:ok, {:ok, meta}} -> meta end)

    # If any upload failed, return error with metadata for rollback
    if failures != [] do
      first_failure =
        case Enum.at(failures, 0) do
          {:ok, {:error, reason}} -> reason
          {:exit, reason} -> {:task_exit, reason}
          _ -> :unknown_error
        end

      {:error, :upload_failed, first_failure, uploaded_metadata}
    else
      {:ok, uploaded_metadata}
    end
  end

  # Create all photos in DB atomically using Ecto.Multi
  # If any photo fails to create, the transaction rolls back
  defp create_photos_atomically(album, photos_metadata) do
    multi =
      photos_metadata
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {metadata, index}, multi ->
        Multi.run(multi, {:create_photo, index}, fn _repo, _changes ->
          Photography.create_photo(%{
            album_id: album.id,
            file_path: metadata.storage_path,
            hash: metadata.hash,
            original_filename: metadata.original_filename,
            display_order: index
          })
        end)
      end)

    case Repo.transaction(multi) do
      {:ok, results} ->
        # Extract created photos from results
        photos =
          results
          |> Enum.filter(fn {{key, _index}, _photo} -> key == :create_photo end)
          |> Enum.map(fn {_key, photo} -> photo end)

        {:ok, photos}

      {:error, {:create_photo, _index}, changeset, _changes} ->
        # Photo creation failed, rollback files
        rollback_uploaded_files(photos_metadata)
        {:error, changeset}

      {:error, _step, reason, _changes} ->
        rollback_uploaded_files(photos_metadata)
        {:error, reason}
    end
  end

  # Delete uploaded files from storage in case of rollback
  # Logs failures but always returns :ok since rollback is best-effort
  defp rollback_uploaded_files(photos_metadata) do
    failed_deletions =
      photos_metadata
      |> Enum.map(fn metadata ->
        case storage().delete_photo(metadata.photo_id) do
          :ok ->
            nil

          {:error, reason} ->
            Logger.error("Rollback deletion failed",
              photo_id: metadata.photo_id,
              reason: inspect(reason)
            )

            metadata.photo_id
        end
      end)
      |> Enum.reject(&is_nil/1)

    if failed_deletions != [] do
      Logger.error(
        "Rollback incomplete - orphaned files may exist: #{inspect(failed_deletions)} (count: #{length(failed_deletions)})"
      )
    end

    :ok
  end

  defp storage do
    Application.get_env(:portfolio, :file_storage)[:backend] ||
      Portfolio.Photography.Storage.LocalStorage
  end

  # Validate file sizes before processing to prevent DOS attacks
  defp validate_upload_sizes(uploads, max_size) do
    Enum.reduce_while(uploads, :ok, fn upload, :ok ->
      # Get file size without reading entire file
      case File.stat(upload.path) do
        {:ok, %{size: size}} when size > max_size ->
          {:halt, {:error, {upload.client_name, size}}}

        {:ok, _} ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, {upload.client_name, reason}}}
      end
    end)
  end

  defp get_max_file_size do
    Application.get_env(:portfolio, :uploads)[:max_file_size] || 10_485_760
  end
end
