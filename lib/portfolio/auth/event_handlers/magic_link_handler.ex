defmodule Portfolio.Auth.EventHandlers.MagicLinkHandler do
  @moduledoc """
  Event handler for MagicLink domain events.

  This handler reacts to magic link events (requested and verified) and can
  trigger various side effects such as:
  - Logging authentication events
  - Tracking login attempts and metrics
  - Implementing rate limiting
  - Updating user last_login timestamp
  - Triggering welcome notifications for new users

  The handler runs as a GenServer and subscribes to:
  - `:magic_link_requested` - When a user requests authentication
  - `:magic_link_verified` - When a user successfully authenticates

  ## Architecture

  This handler is part of the Application Layer and coordinates
  infrastructure concerns (logging, metrics, notifications) in response
  to domain events.

  ## Supervision

  This GenServer is supervised by the main application supervisor
  and will restart automatically if it crashes.
  """

  use GenServer
  require Logger

  alias Portfolio.DomainEvents
  alias Portfolio.Auth.Events.{MagicLinkRequested, MagicLinkVerified}

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
    # Subscribe to both magic link events
    DomainEvents.subscribe(:magic_link_requested)
    DomainEvents.subscribe(:magic_link_verified)

    Logger.info(
      "MagicLinkHandler started and subscribed to :magic_link_requested and :magic_link_verified events"
    )

    {:ok, %{}}
  end

  @impl true
  def handle_info({:magic_link_requested, %MagicLinkRequested{} = event}, state) do
    Logger.info("Magic link requested",
      magic_link_id: event.magic_link_id,
      email: event.email,
      requested_at: event.requested_at,
      expires_at: event.expires_at
    )

    # Future enhancements:
    # - Track authentication request metrics
    # - Implement rate limiting per email
    # - Detect suspicious login patterns
    # - Log failed authentication attempts

    {:noreply, state}
  end

  @impl true
  def handle_info({:magic_link_verified, %MagicLinkVerified{} = event}, state) do
    Logger.info("Magic link verified - User authenticated",
      magic_link_id: event.magic_link_id,
      user_id: event.user_id,
      email: event.email,
      verified_at: event.verified_at
    )

    # Future enhancements:
    # - Update user.last_login_at timestamp
    # - Send welcome email for new users
    # - Track successful authentication metrics
    # - Log security events

    {:noreply, state}
  end

  # Handle unexpected messages gracefully
  @impl true
  def handle_info(msg, state) do
    Logger.warning("MagicLinkHandler received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end
