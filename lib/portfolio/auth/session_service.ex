defmodule Portfolio.Auth.SessionService do
  @moduledoc """
  Service for managing user sessions.

  Responsibilities:
  - Creating sessions after successful authentication
  - Retrieving sessions (by token, by ID, by user)
  - Updating activity (session extension)
  - Deleting sessions (logout)
  - Cleaning up expired sessions
  - Emitting domain events

  This service encapsulates all business logic for user sessions,
  including secure token generation, expiration management,
  and multi-device logout.

  Delegates persistence to SessionRepository to respect the Repository pattern.

  ## Expiration Policy

  Sessions expire after 30 days of inactivity.
  Activity is automatically updated on each authenticated request
  via the RequireAuth plug.
  """

  alias Portfolio.Auth.Events.SessionCreated
  alias Portfolio.Auth.Repositories.SessionRepository
  alias Portfolio.Auth.{User, UserSession}
  alias Portfolio.CacheManager
  alias Portfolio.DomainEvents
  alias Portfolio.RateLimiter

  # =============================================================================
  # Creation Functions
  # =============================================================================

  @doc """
  Creates a new session for a user after successful login.

  Generates a secure 32-byte token and initializes the session
  with the current activity date.

  IMPORTANT: The token returned in the session is in plaintext (raw_token).
  In the DB, the token is stored hashed for security.
  This allows storing the plaintext token in the user cookie
  while protecting against token theft if the DB is compromised.

  Emits a `SessionCreated` event to notify other contexts.

  ## Examples

      iex> create_session(user)
      {:ok, %UserSession{token: "abc123..."}}  # Plaintext token

      iex> create_session(nil)
      ** (FunctionClauseError) no function clause matching
  """
  @spec create_session(User.t()) ::
          {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()} | {:error, :rate_limit_exceeded}
  def create_session(%User{} = user) do
    # Rate limit session creation to prevent DoS via unlimited sessions
    case RateLimiter.check_rate(:session_creation, user.id) do
      {:deny, _retry_after} ->
        {:error, :rate_limit_exceeded}

      {:allow, _remaining} ->
        do_create_session(user)
    end
  end

  @spec do_create_session(User.t()) :: {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  defp do_create_session(%User{} = user) do
    raw_token = generate_token()

    result =
      SessionRepository.insert(%{
        user_id: user.id,
        token: raw_token,
        last_activity_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    # Restore the plaintext token in the returned session
    # (in DB it's hashed, but we want the plaintext token for the cookie)
    case result do
      {:ok, session} ->
        session_with_raw_token = %{session | token: raw_token}
        publish_session_created_event(session_with_raw_token, user)
        {:ok, session_with_raw_token}

      {:error, _changeset} = error ->
        error
    end
  end

  # =============================================================================
  # Query Functions
  # =============================================================================

  @doc """
  Retrieves a session by its token.

  Returns nil if the token doesn't exist or if the session has expired.
  Expired sessions are automatically deleted.

  IMPORTANT: The provided token must be the plaintext token (the one stored in the cookie).
  It will be automatically hashed before the DB lookup since tokens are
  stored hashed for security.

  ## Examples

      iex> get_session_by_token("valid_token")
      %UserSession{user: %User{}}

      iex> get_session_by_token("invalid_token")
      nil

      iex> get_session_by_token("expired_token")
      nil  # Expired session automatically deleted
  """
  @spec get_session_by_token(String.t()) :: UserSession.t() | nil
  def get_session_by_token(token) when is_binary(token) do
    # Hash the token for DB lookup (tokens are stored hashed)
    hashed_token = UserSession.hash_token_value(token)

    case SessionRepository.get_by_token(hashed_token, preload: [:user]) do
      {:ok, session} -> validate_session_not_expired(session)
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Retrieves a session by its ID.

  Raises an exception if the session doesn't exist.

  ## Examples

      iex> get_session!("123e4567-e89b-12d3-a456-426614174000")
      %UserSession{}

      iex> get_session!("invalid-uuid")
      ** (Ecto.NoResultsError)
  """
  @spec get_session!(Ecto.UUID.t()) :: UserSession.t()
  def get_session!(id), do: SessionRepository.get!(id)

  @doc """
  Reloads the session's user from the database.

  This function retrieves fresh user data (especially the role)
  even if the session is cached. This ensures role changes
  are immediately visible.

  ## Examples

      iex> session = get_session_by_token(token)
      iex> fresh_session = reload_user(session)
      iex> fresh_session.user.role
      :admin

  """
  @spec reload_user(UserSession.t()) :: UserSession.t()
  def reload_user(%UserSession{} = session) do
    SessionRepository.reload_user(session)
  end

  @doc """
  Lists all sessions for a user sorted by last activity.

  Most recent sessions appear first.

  ## Examples

      iex> list_user_sessions(user.id)
      [%UserSession{}, ...]

      iex> list_user_sessions("user-without-sessions")
      []
  """
  @spec list_user_sessions(Ecto.UUID.t()) :: [UserSession.t()]
  def list_user_sessions(user_id) do
    SessionRepository.list_by_user(user_id)
  end

  # =============================================================================
  # Update Functions
  # =============================================================================

  @doc """
  Updates a session's activity (to extend its lifetime).

  Called automatically by RequireAuth on each authenticated request.

  **Throttling**: To avoid DB overload, the update is only performed
  if the last update was more than 5 minutes ago. This drastically reduces
  the number of DB writes without impacting UX.

  ## Configuration

  The throttling interval is configurable via:

      config :portfolio, :auth,
        activity_update_throttle_seconds: 5 * 60  # 5 minutes by default

  ## Examples

      iex> update_session_activity(session)
      {:ok, %UserSession{last_activity_at: ~U[2024-01-15 10:30:00Z]}}

      iex> update_session_activity(session_recently_updated)
      {:ok, %UserSession{last_activity_at: ~U[2024-01-15 10:25:00Z]}}  # No update
  """
  @spec update_session_activity(UserSession.t()) ::
          {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  def update_session_activity(%UserSession{} = session) do
    throttle_seconds = get_activity_update_throttle()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Calculate time elapsed since last activity
    seconds_since_last_activity = DateTime.diff(now, session.last_activity_at, :second)

    # Only update if throttle threshold exceeded
    if seconds_since_last_activity >= throttle_seconds do
      SessionRepository.update_activity(session, now)
    else
      # No update needed, return session unchanged
      {:ok, session}
    end
  end

  # Retrieves the throttling interval from configuration
  @spec get_activity_update_throttle() :: integer()
  defp get_activity_update_throttle do
    Application.get_env(:portfolio, :auth, [])
    |> Keyword.get(:activity_update_throttle_seconds, 5 * 60)
  end

  # =============================================================================
  # Delete Functions
  # =============================================================================

  @doc """
  Deletes a session (logout from one device).

  ## Examples

      iex> delete_session(session)
      {:ok, %UserSession{}}
  """
  @spec delete_session(UserSession.t()) :: {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  def delete_session(%UserSession{} = session) do
    result = SessionRepository.delete(session)

    # Invalidate session cache to prevent it from remaining active
    invalidate_session_cache(session.token)

    result
  end

  @doc """
  Deletes all sessions for a user (logout from all devices).

  Useful for revoking access from all devices in case of compromise.

  ## Examples

      iex> delete_all_user_sessions(user)
      {3, nil}  # 3 sessions deleted
  """
  @spec delete_all_user_sessions(User.t()) :: {integer(), nil}
  def delete_all_user_sessions(%User{id: user_id}) do
    delete_user_sessions_with_cache_invalidation(
      user_id,
      fn sessions -> Enum.map(sessions, & &1.token) end,
      fn -> SessionRepository.delete_all_for_user(user_id) end
    )
  end

  @doc """
  Deletes all sessions for a user except the specified one.

  Useful for logging out all other devices while keeping the current session.

  ## Examples

      iex> delete_all_user_sessions_except(user, current_session.id)
      {2, nil}  # 2 other sessions deleted

      iex> delete_all_user_sessions_except(user, "only-session-id")
      {0, nil}  # No other sessions
  """
  @spec delete_all_user_sessions_except(User.t(), Ecto.UUID.t()) :: {integer(), nil}
  def delete_all_user_sessions_except(%User{id: user_id}, current_session_id) do
    delete_user_sessions_with_cache_invalidation(
      user_id,
      fn sessions ->
        sessions |> Enum.reject(&(&1.id == current_session_id)) |> Enum.map(& &1.token)
      end,
      fn -> SessionRepository.delete_all_for_user_except(user_id, current_session_id) end
    )
  end

  # Helper to delete sessions with cache invalidation
  # Extracts common logic between delete_all_user_sessions and delete_all_user_sessions_except
  @spec delete_user_sessions_with_cache_invalidation(
          Ecto.UUID.t(),
          (list() -> [String.t()]),
          (-> {integer(), nil})
        ) :: {integer(), nil}
  defp delete_user_sessions_with_cache_invalidation(user_id, token_extractor, delete_fn) do
    sessions = SessionRepository.list_by_user(user_id)
    tokens = token_extractor.(sessions)

    result = delete_fn.()

    Enum.each(tokens, &invalidate_session_cache/1)

    result
  end

  @doc """
  Deletes all expired sessions (cleanup job).

  Should be called periodically (for example, via a cron job or Oban worker).

  ## Examples

      iex> delete_expired_sessions()
      {10, nil}  # 10 expired sessions deleted
  """
  @spec delete_expired_sessions() :: {integer(), nil}
  def delete_expired_sessions do
    expiry_seconds = UserSession.session_expiration_seconds()
    SessionRepository.delete_expired(expiry_seconds)
  end

  # =============================================================================
  # Private Functions - Token Generation
  # =============================================================================

  # Generates a secure 32-byte token
  @spec generate_token() :: String.t()
  defp generate_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  # =============================================================================
  # Private Functions - Cache Invalidation
  # =============================================================================

  # Invalidates session cache by token (raw or hashed)
  @spec invalidate_session_cache(String.t()) :: :ok
  defp invalidate_session_cache(token) when is_binary(token) do
    CacheManager.invalidate_session(token)
  end

  # =============================================================================
  # Private Functions - Session Creation
  # =============================================================================

  # Publishes the session creation event
  @spec publish_session_created_event(UserSession.t(), User.t()) :: :ok
  defp publish_session_created_event(session, user) do
    max_age_days = get_session_max_age()
    expires_at = DateTime.add(session.last_activity_at, max_age_days, :day)

    DomainEvents.publish(:session_created, %SessionCreated{
      session_id: session.id,
      user_id: user.id,
      email: user.email,
      created_at: session.inserted_at,
      expires_at: expires_at
    })
  end

  # Retrieves the maximum session lifetime from configuration
  @spec get_session_max_age() :: integer()
  defp get_session_max_age do
    Application.get_env(:portfolio, :auth, [])
    |> Keyword.get(:session_max_age_days, 30)
  end

  # =============================================================================
  # Private Functions - Session Validation
  # =============================================================================

  # Validates that a session is not expired, otherwise deletes it
  @spec validate_session_not_expired(UserSession.t()) :: UserSession.t() | nil
  defp validate_session_not_expired(session) do
    if UserSession.expired?(session) do
      _ = delete_session(session)
      nil
    else
      session
    end
  end
end
