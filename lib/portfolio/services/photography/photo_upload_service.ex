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
        max_concurrency = Keyword.get(opts, :max_concurrency, 4)
        timeout = Keyword.get(opts, :timeout, 30_000)
        ordered = Keyword.get(opts, :ordered, false)

        # Upload in parallel with Task.async_stream
        results =
          uploads
          |> Task.async_stream(
            fn upload -> storage().store_photo(album_slug, upload) end,
            max_concurrency: max_concurrency,
            timeout: timeout,
            ordered: ordered,
            on_timeout: :kill_task
          )
          |> Enum.to_list()

        # Check if all operations succeeded
        if Enum.all?(results, &match?({:ok, {:ok, _}}, &1)) do
          photos_metadata = Enum.map(results, fn {:ok, {:ok, meta}} -> meta end)
          {:ok, photos_metadata}
        else
          # Get the first error
          case Enum.find(results, &match?({:ok, {:error, _}}, &1)) do
            {:ok, {:error, reason}} -> {:error, reason}
            {:exit, reason} -> {:error, {:task_exit, reason}}
            nil -> {:error, :unknown_error}
          end
        end
      end
    )
  end

  defp storage do
    Application.get_env(:portfolio, :file_storage)[:backend] ||
      Portfolio.Photography.Storage.LocalStorage
  end
end
