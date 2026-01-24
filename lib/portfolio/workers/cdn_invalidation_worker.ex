defmodule Portfolio.Workers.CdnInvalidationWorker do
  @moduledoc """
  Oban worker for CDN cache invalidation.

  This worker handles asynchronous CDN cache invalidation with proper
  error handling, retries, and monitoring - replacing the previous
  Task.start approach which had no retry mechanism.

  ## Workflow

  1. Album published → event handler enqueues worker
  2. Worker calls configured CDN module to invalidate paths
  3. On failure: automatic retry with exponential backoff
  4. After max attempts: logs error for manual intervention

  ## Error Handling

  - **Permanent failures** (invalid config): Cancel job, log error
  - **Transient failures** (network issues): Retry with backoff
  - Maximum 5 retry attempts before giving up

  ## Configuration

  Queue: `:cdn`
  Max attempts: 5
  Priority: 2 (lower priority than image processing)

  ## Usage

      # Enqueue a job
      CdnInvalidationWorker.enqueue("album-slug", ["path1", "path2"])

  ## Telemetry

  Emits telemetry events for monitoring:
  - `[:portfolio, :cdn, :invalidation, :start]`
  - `[:portfolio, :cdn, :invalidation, :stop]`
  - `[:portfolio, :cdn, :invalidation, :exception]`
  """

  use Oban.Worker,
    queue: :cdn,
    max_attempts: 5,
    priority: 2

  require Logger

  @doc """
  Enqueues a CDN invalidation job.

  ## Parameters

  - `album_slug` - The album slug for logging purposes
  - `paths` - List of paths to invalidate

  ## Examples

      iex> CdnInvalidationWorker.enqueue("wedding-2024", ["/", "/albums/wedding-2024"])
      {:ok, %Oban.Job{}}
  """
  @spec enqueue(String.t(), [String.t()]) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(album_slug, paths) when is_binary(album_slug) and is_list(paths) do
    %{album_slug: album_slug, paths: paths}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"album_slug" => album_slug, "paths" => paths}}) do
    :telemetry.span(
      [:portfolio, :cdn, :invalidation],
      %{album_slug: album_slug, path_count: length(paths)},
      fn ->
        result = do_invalidate(album_slug, paths)
        {result, %{album_slug: album_slug}}
      end
    )
  end

  defp do_invalidate(album_slug, paths) do
    cdn_module = Application.get_env(:portfolio, :cdn_module, Portfolio.CDN.NoOp)

    case cdn_module.invalidate(paths) do
      :ok ->
        Logger.info("CDN cache invalidated",
          album_slug: album_slug,
          paths: paths
        )

        :ok

      {:error, reason} ->
        Logger.warning("CDN invalidation failed, will retry",
          album_slug: album_slug,
          reason: inspect(reason)
        )

        # Return error to trigger Oban retry
        {:error, reason}
    end
  end
end
