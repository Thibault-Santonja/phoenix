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

    # Future enhancements:
    # - Send notifications to subscribers
    # - Update search index
    # - Trigger social media posting
    # - Update analytics/metrics

    {:noreply, state}
  end

  # Handle unexpected messages gracefully
  @impl true
  def handle_info(msg, state) do
    Logger.warning("AlbumPublishedHandler received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end
