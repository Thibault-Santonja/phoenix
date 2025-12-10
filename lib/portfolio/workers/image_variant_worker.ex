defmodule Portfolio.Workers.ImageVariantWorker do
  @moduledoc """
  Oban worker for generating image variants asynchronously.

  This worker processes photo uploads in the background to generate
  optimized WebP variants without blocking the upload request.

  ## Workflow

  1. Photo uploaded → original stored immediately
  2. Worker job enqueued with photo_id
  3. Worker generates variants (thumbnail, small, medium, large)
  4. Photo record updated with variant URLs and status

  ## Error Handling

  - **Permanent failures** (file not found, corrupted): Cancel job, mark photo as failed
  - **Transient failures** (I/O errors, temporary issues): Retry with exponential backoff
  - Maximum 3 retry attempts before marking as failed

  ## Configuration

  Queue: `:image_processing`
  Max attempts: 3
  Priority: 1 (higher = lower priority)

  ## Usage

      # Enqueue a job
      %{photo_id: "a3f2b8c4"}
      |> ImageVariantWorker.new()
      |> Oban.insert()

  ## Telemetry

  Emits telemetry events for monitoring:
  - `[:portfolio, :image, :processing, :start]`
  - `[:portfolio, :image, :processing, :stop]`
  - `[:portfolio, :image, :processing, :exception]`
  """

  use Oban.Worker,
    queue: :image_processing,
    max_attempts: 3,
    priority: 1

  require Logger

  alias Portfolio.Photography

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_id" => photo_id}, attempt: attempt}) do
    Logger.metadata(photo_id: photo_id, attempt: attempt)

    Logger.info("Starting image variant generation", photo_id: photo_id, attempt: attempt)

    start_time = System.monotonic_time(:millisecond)

    :telemetry.execute(
      [:portfolio, :image, :processing, :start],
      %{system_time: System.system_time()},
      %{photo_id: photo_id}
    )

    storage_adapter = get_storage_adapter()

    result =
      case storage_adapter.generate_variants(photo_id) do
        {:ok, variants} ->
          duration = System.monotonic_time(:millisecond) - start_time

          Logger.info("Image variants generated successfully",
            photo_id: photo_id,
            duration_ms: duration,
            variant_count: map_size(variants)
          )

          :telemetry.execute(
            [:portfolio, :image, :processing, :stop],
            %{duration: duration},
            %{photo_id: photo_id, variant_count: map_size(variants)}
          )

          update_photo_with_variants(photo_id, variants)

        {:error, :file_not_found} = error ->
          # Permanent error - photo doesn't exist, don't retry
          Logger.error("Photo file not found - cancelling job",
            photo_id: photo_id,
            attempt: attempt
          )

          :telemetry.execute(
            [:portfolio, :image, :processing, :exception],
            %{},
            %{photo_id: photo_id, reason: :file_not_found}
          )

          mark_photo_as_failed(photo_id, :file_not_found)
          {:cancel, error}

        {:error, :corrupted_file} = error ->
          # Permanent error - file is corrupted, don't retry
          Logger.error("Photo file is corrupted - cancelling job",
            photo_id: photo_id,
            attempt: attempt
          )

          :telemetry.execute(
            [:portfolio, :image, :processing, :exception],
            %{},
            %{photo_id: photo_id, reason: :corrupted_file}
          )

          mark_photo_as_failed(photo_id, :corrupted_file)
          {:cancel, error}

        {:error, :service_unavailable} ->
          # Circuit breaker is open - retry later with snooze
          Logger.warning("Image processing circuit breaker open - snoozing job",
            photo_id: photo_id,
            attempt: attempt
          )

          :telemetry.execute(
            [:portfolio, :image, :processing, :exception],
            %{},
            %{photo_id: photo_id, reason: :circuit_breaker_open, will_retry: true}
          )

          # Snooze for 30 seconds to wait for circuit breaker to reset
          {:snooze, 30}

        {:error, reason} = error ->
          # Transient error - retry
          Logger.warning("Image processing failed, will retry",
            photo_id: photo_id,
            attempt: attempt,
            max_attempts: 3,
            reason: inspect(reason)
          )

          :telemetry.execute(
            [:portfolio, :image, :processing, :exception],
            %{},
            %{photo_id: photo_id, reason: reason, will_retry: attempt < 3}
          )

          # Let Oban handle the retry
          error
      end

    result
  end

  @doc """
  Enqueue a job to generate variants for a photo.

  ## Examples

      iex> ImageVariantWorker.enqueue("a3f2b8c4")
      {:ok, %Oban.Job{}}
  """
  @spec enqueue(String.t()) :: {:ok, Oban.Job.t()} | {:error, Oban.Job.changeset()}
  def enqueue(photo_id) do
    %{photo_id: photo_id}
    |> new()
    |> Oban.insert()
  end

  # Private functions

  defp get_storage_adapter do
    Application.get_env(:portfolio, :file_storage)[:backend] ||
      Portfolio.Photography.Storage.LocalStorage
  end

  defp update_photo_with_variants(photo_id, variants) do
    # Try to update photo in database if it exists
    # This is optional - the worker can complete successfully even if the photo
    # is not in the database (e.g., during testing or standalone usage)
    case Photography.get_photo(photo_id) do
      {:error, :not_found} ->
        Logger.info("Photo not in database, variants generated successfully",
          photo_id: photo_id,
          variant_count: map_size(variants)
        )

        :ok

      {:ok, photo} ->
        attrs = %{
          variants: variants,
          processing_status: :completed
        }

        case Photography.update_photo(photo, attrs) do
          {:ok, _updated_photo} ->
            Logger.info("Photo updated with variants",
              photo_id: photo_id,
              variant_count: map_size(variants)
            )

            :ok

          {:error, changeset} ->
            Logger.error("Failed to update photo",
              photo_id: photo_id,
              errors: inspect(changeset.errors)
            )

            # Still return :ok as the variants were generated successfully
            :ok
        end
    end
  rescue
    error ->
      Logger.warning("Could not update photo record",
        photo_id: photo_id,
        error: inspect(error)
      )

      # Variants were generated successfully, so return :ok
      :ok
  end

  defp mark_photo_as_failed(photo_id, reason) do
    # Try to mark photo as failed in database if it exists
    # This is optional - failures can still be logged even if the photo
    # is not in the database (e.g., during testing or standalone usage)
    case Photography.get_photo(photo_id) do
      {:error, :not_found} ->
        Logger.warning("Photo not in database",
          photo_id: photo_id,
          reason: :photo_not_found
        )

        :ok

      {:ok, photo} ->
        attrs = %{
          processing_status: :failed,
          processing_error: Atom.to_string(reason)
        }

        case Photography.update_photo(photo, attrs) do
          {:ok, _updated_photo} ->
            Logger.info("Photo marked as failed",
              photo_id: photo_id,
              reason: reason
            )

            :ok

          {:error, changeset} ->
            Logger.error("Failed to mark photo as failed",
              photo_id: photo_id,
              errors: inspect(changeset.errors)
            )

            :ok
        end
    end
  rescue
    error ->
      Logger.warning("Could not update photo status",
        photo_id: photo_id,
        error: inspect(error)
      )

      :ok
  end
end
