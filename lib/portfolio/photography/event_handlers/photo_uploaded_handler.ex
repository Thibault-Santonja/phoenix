defmodule Portfolio.Photography.EventHandlers.PhotoUploadedHandler do
  @moduledoc """
  Event handler for PhotoUploaded domain events.

  This handler reacts to photo upload events and can trigger
  various side effects such as:
  - Logging upload events
  - Generating thumbnails
  - Extracting EXIF metadata
  - Running image processing pipelines
  - Updating album statistics
  - Tracking storage metrics

  The handler runs as a GenServer and subscribes to the `:photo_uploaded`
  event type via the DomainEvents system.

  ## Architecture

  This handler is part of the Application Layer and coordinates
  infrastructure concerns (image processing, logging, etc.) in response
  to domain events.

  ## Supervision

  This GenServer is supervised by the main application supervisor
  and will restart automatically if it crashes.
  """

  use GenServer
  require Logger

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.Events.PhotoUploaded
  alias Portfolio.Workers.ExifExtractionWorker

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Starts the event handler GenServer.

  Called by the supervision tree during application startup.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    # Subscribe to photo_uploaded events
    DomainEvents.subscribe(:photo_uploaded)
    Logger.info("PhotoUploadedHandler started and subscribed to :photo_uploaded events")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:photo_uploaded, %PhotoUploaded{} = event}, state) do
    Logger.info("Photo uploaded",
      photo_id: event.photo_id,
      album_id: event.album_id,
      file_path: event.file_path,
      hash: event.hash,
      uploaded_at: event.uploaded_at
    )

    # Enqueue EXIF extraction job in Oban (persistent, retryable)
    %{photo_id: event.photo_id}
    |> ExifExtractionWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.debug("EXIF extraction job enqueued", photo_id: event.photo_id)

      {:error, reason} ->
        Logger.error("Failed to enqueue EXIF extraction job",
          photo_id: event.photo_id,
          reason: inspect(reason)
        )
    end

    {:noreply, state}
  end

  # Handle unexpected messages gracefully
  @impl true
  def handle_info(msg, state) do
    Logger.warning("PhotoUploadedHandler received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end
