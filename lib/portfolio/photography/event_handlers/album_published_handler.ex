defmodule Portfolio.Photography.EventHandlers.AlbumPublishedHandler do
  @moduledoc """
  Event handler for AlbumPublished domain events.

  This handler reacts to album publication events and can trigger
  various side effects such as:
  - Logging publication events
  - Sending notifications to subscribers
  - Updating search indexes
  - Triggering social media sharing
  - Updating analytics

  The handler runs as a GenServer and subscribes to the `:album_published`
  event type via the DomainEvents system.

  ## Architecture

  This handler is part of the Application Layer and coordinates
  infrastructure concerns (logging, notifications, etc.) in response
  to domain events.

  ## Supervision

  This GenServer is supervised by the main application supervisor
  and will restart automatically if it crashes.
  """

  use GenServer
  require Logger

  alias Portfolio.CacheManager
  alias Portfolio.DomainEvents
  alias Portfolio.Photography.Events.AlbumPublished
  alias Portfolio.Workers.CdnInvalidationWorker

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
    # Subscribe to album_published events
    _ = DomainEvents.subscribe(:album_published)
    Logger.info("AlbumPublishedHandler started and subscribed to :album_published events")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:album_published, %AlbumPublished{} = event}, state) do
    Logger.info("Album published",
      album_id: event.album_id,
      title: event.title,
      slug: event.slug,
      published_at: event.published_at,
      user_id: event.user_id
    )

    # Invalidate CDN cache via Oban worker (resilient with retries)
    enqueue_cdn_invalidation(event)

    # Clear application cache
    clear_albums_cache()

    {:noreply, state}
  end

  # Handle unexpected messages gracefully
  @impl true
  def handle_info(msg, state) do
    Logger.warning("AlbumPublishedHandler received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  @spec enqueue_cdn_invalidation(AlbumPublished.t()) :: :ok
  defp enqueue_cdn_invalidation(event) do
    paths_to_invalidate = [
      "/",
      "/albums",
      "/albums/#{event.slug}",
      "/api/albums",
      "/api/albums/#{event.slug}"
    ]

    case CdnInvalidationWorker.enqueue(event.slug, paths_to_invalidate) do
      {:ok, _job} ->
        Logger.debug("CDN invalidation job enqueued", album_slug: event.slug)
        :ok

      {:error, reason} ->
        # Log but don't crash - CDN invalidation is best-effort
        Logger.warning("Failed to enqueue CDN invalidation",
          album_slug: event.slug,
          reason: inspect(reason)
        )

        :ok
    end
  end

  @spec clear_albums_cache() :: :ok
  defp clear_albums_cache do
    CacheManager.invalidate_albums()
  end
end
