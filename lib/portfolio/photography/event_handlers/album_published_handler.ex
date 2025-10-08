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

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.Events.AlbumPublished

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
    DomainEvents.subscribe(:album_published)
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

    # Invalidate CDN cache asynchronously
    Task.start(fn -> invalidate_cdn_cache(event) end)

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

  @spec invalidate_cdn_cache(AlbumPublished.t()) :: :ok | {:error, term()}
  defp invalidate_cdn_cache(event) do
    cdn_module = Application.get_env(:portfolio, :cdn_module, Portfolio.CDN.NoOp)

    paths_to_invalidate = [
      "/",
      "/albums",
      "/albums/#{event.slug}",
      "/api/albums",
      "/api/albums/#{event.slug}"
    ]

    case cdn_module.invalidate(paths_to_invalidate) do
      :ok ->
        Logger.info("CDN cache invalidated",
          album_slug: event.slug,
          paths: paths_to_invalidate
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to invalidate CDN cache",
          album_slug: event.slug,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @spec clear_albums_cache() :: :ok
  defp clear_albums_cache do
    # Clear Cachex cache for albums
    case Cachex.clear(:albums_cache) do
      {:ok, _} ->
        Logger.debug("Albums cache cleared")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to clear albums cache", reason: inspect(reason))
        :ok
    end
  end
end
