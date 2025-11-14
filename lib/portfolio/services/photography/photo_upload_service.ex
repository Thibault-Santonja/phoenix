defmodule Portfolio.Services.Photography.PhotoUploadService do
  @moduledoc """
  Service for uploading photos with parallel processing.

  Responsibilities:
  - Parallel file upload using Task.async_stream
  - Error handling and recovery
  - Telemetry tracking
  - Storage abstraction

  This service encapsulates the complex workflow of uploading multiple photos
  in parallel, handling errors, timeouts, and tracking performance metrics.
  """

  use Portfolio.Services.Service

  alias Ecto.Multi
  alias Portfolio.Photography
  alias Portfolio.Repo

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
  - `{:error, reason}` - Upload failed

  ## Examples

      iex> execute("wedding-2024", [upload1, upload2], max_concurrency: 8)
      {:ok, [%{file_path: "...", hash: "..."}, ...]}

      iex> execute("invalid-album", [upload])
      {:error, :album_not_found}
  """
  @spec execute(String.t(), [map()], keyword()) :: {:ok, [map()]} | {:error, term()}
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
  defp rollback_uploaded_files(photos_metadata) do
    Enum.each(photos_metadata, fn metadata ->
      storage().delete_photo(metadata.photo_id)
    end)

    :ok
  end

  defp storage do
    Application.get_env(:portfolio, :file_storage)[:backend] ||
      Portfolio.Photography.Storage.LocalStorage
  end
end
