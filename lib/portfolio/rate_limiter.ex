defmodule Portfolio.RateLimiter do
  @moduledoc """
  Rate limiting service using Hammer's ETS backend.

  This module wraps Hammer.ETS.FixWindow directly instead of using `use Hammer`
  to avoid compilation-time ETS table creation issues during parallel test compilation.

  Provides rate limiting for various operations to prevent abuse:
  - Magic link requests (email-based authentication)
  - Login attempts
  - API endpoints

  ## Configuration

  Rate limits are defined per action:

  - `:magic_link_request` - 5 requests per hour per email
  - `:login_attempt` - 10 attempts per hour per IP

  ## Examples

      iex> RateLimiter.check_rate(:magic_link_request, "user@example.com")
      {:allow, 4}  # 4 requests remaining

      iex> RateLimiter.check_rate(:magic_link_request, "spammer@example.com")
      {:deny, 0}  # Rate limit exceeded
  """

  use GenServer

  require Logger

  @table __MODULE__

  @type action ::
          :magic_link_request
          | :magic_link_verify
          | :login_attempt
          | :session_creation
          | :photo_upload
          | :album_creation
          | :bulk_delete
  @type rate_identifier :: String.t()
  @type result :: {:allow, remaining :: integer()} | {:deny, retry_after :: integer()}

  # Rate limit configurations (limit, period in milliseconds)
  @rate_limits %{
    # 5 magic link requests per hour per email
    magic_link_request: {5, :timer.hours(1)},
    # 10 magic link verification attempts per 5 minutes per IP (prevents brute force)
    magic_link_verify: {10, :timer.minutes(5)},
    # 10 login attempts per hour per IP
    login_attempt: {10, :timer.hours(1)},
    # 20 session creations per hour per user (prevents DoS via unlimited sessions)
    session_creation: {20, :timer.hours(1)},
    # 50 photo uploads per 10 minutes per user (prevents disk I/O exhaustion)
    photo_upload: {50, :timer.minutes(10)},
    # 10 album creations per hour per user (prevents database spam)
    album_creation: {10, :timer.hours(1)},
    # 5 bulk delete operations per minute per user (prevents mass deletion abuse)
    bulk_delete: {5, :timer.minutes(1)}
  }

  # GenServer API

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    clean_period = Keyword.get(opts, :clean_period, :timer.minutes(1))

    # Create the ETS table with Hammer-compatible options
    _table =
      :ets.new(@table, [
        :named_table,
        :set,
        :public,
        {:read_concurrency, true},
        {:write_concurrency, true},
        {:decentralized_counters, true}
      ])

    # Schedule periodic cleanup
    schedule_cleanup(clean_period)

    {:ok, %{clean_period: clean_period}}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    clean_expired_entries()
    schedule_cleanup(state.clean_period)
    {:noreply, state}
  end

  # Public API

  @doc """
  Checks if an action is allowed for a given identifier.

  ## Parameters

  - `action` - Type of action to rate limit (atom)
  - `identifier` - Unique identifier (email, IP, user_id, etc.)

  ## Returns

  - `{:allow, remaining}` - Action allowed, number of remaining requests
  - `{:deny, retry_after}` - Action denied, retry time in milliseconds

  ## Examples

      iex> check_rate(:magic_link_request, "user@example.com")
      {:allow, 4}

      iex> check_rate(:magic_link_request, "spammer@example.com")
      {:deny, 3540000}  # ~59 minutes
  """
  @spec check_rate(action(), rate_identifier()) ::
          {:allow, non_neg_integer()} | {:deny, non_neg_integer()}
  def check_rate(action, identifier) when is_atom(action) and is_binary(identifier) do
    {limit, period} = Map.fetch!(@rate_limits, action)
    bucket_key = build_bucket_key(action, identifier)

    start_time = System.monotonic_time()

    result = hit(bucket_key, period, limit)

    # Emit telemetry event
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:portfolio, :rate_limiter, :check],
      %{duration: duration},
      %{
        action: action,
        identifier: identifier,
        result: elem(result, 0),
        remaining: if(elem(result, 0) == :allow, do: elem(result, 1), else: nil),
        retry_after_ms: if(elem(result, 0) == :deny, do: elem(result, 1), else: nil)
      }
    )

    result
  end

  @doc """
  Resets the counter for a given action and identifier.

  Useful for tests or for manually resetting a rate limit.

  ## Examples

      iex> reset(:magic_link_request, "user@example.com")
      :ok
  """
  @spec reset(action(), rate_identifier()) :: :ok
  def reset(action, identifier) when is_atom(action) and is_binary(identifier) do
    bucket_key = build_bucket_key(action, identifier)
    {_limit, period} = Map.fetch!(@rate_limits, action)

    # Calculate the current window key
    now = System.system_time(:millisecond)
    window = div(now, period)
    full_key = {bucket_key, window}

    # Delete the bucket key directly from ETS table
    try do
      :ets.delete(@table, full_key)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  @doc """
  Resets all rate limit counters.

  Useful for test isolation to ensure rate limit state doesn't bleed between tests.

  ## Examples

      iex> reset_all()
      :ok
  """
  @spec reset_all() :: :ok
  def reset_all do
    try do
      :ets.delete_all_objects(@table)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  @doc """
  Resets rate limit counters for specific actions only.

  Useful for tests that need to preserve rate limit state for some actions
  while resetting others.

  ## Examples

      iex> reset_actions([:magic_link_request, :login_attempt])
      :ok
  """
  @spec reset_actions([action()]) :: :ok
  def reset_actions(actions) when is_list(actions) do
    try do
      :ets.tab2list(@table)
      |> Enum.each(fn {{key, _window}, _count, _expires_at} ->
        key_str = to_string(key)

        should_delete =
          Enum.any?(actions, fn action ->
            String.contains?(key_str, "rate_limit:#{action}:")
          end)

        if should_delete do
          :ets.match_delete(@table, {{key, :_}, :_, :_})
        end
      end)
    rescue
      _ -> :ok
    end

    :ok
  end

  @doc """
  Resets all rate limit counters except for specific actions.

  Useful for tests that need to preserve rate limit buildup for specific
  actions while resetting everything else.

  ## Examples

      iex> reset_all_except([:magic_link_request])
      :ok
  """
  @spec reset_all_except([action()]) :: :ok
  def reset_all_except(actions) when is_list(actions) do
    try do
      :ets.tab2list(@table)
      |> Enum.each(fn {{key, _window}, _count, _expires_at} ->
        key_str = to_string(key)

        should_keep =
          Enum.any?(actions, fn action ->
            String.contains?(key_str, "rate_limit:#{action}:")
          end)

        if not should_keep do
          :ets.match_delete(@table, {{key, :_}, :_, :_})
        end
      end)
    rescue
      _ -> :ok
    end

    :ok
  end

  @doc """
  Returns the configured limits for an action.

  ## Examples

      iex> limit(:magic_link_request)
      {5, 3600000}  # 5 requests per hour
  """
  @spec limit(action()) :: {integer(), integer()}
  def limit(action) when is_atom(action) do
    Map.fetch!(@rate_limits, action)
  end

  # Private functions

  # Hammer-compatible hit function using FixWindow algorithm
  defp hit(key, scale, limit) do
    now = System.system_time(:millisecond)
    window = div(now, scale)
    full_key = {key, window}
    expires_at = (window + 1) * scale

    count = update_counter(full_key, 1, expires_at)

    if count <= limit do
      remaining = limit - count

      Logger.debug("Rate limit check passed",
        bucket_key: key,
        remaining: remaining
      )

      {:allow, remaining}
    else
      retry_after = expires_at - now

      Logger.warning("Rate limit exceeded",
        bucket_key: key,
        retry_after_ms: retry_after
      )

      {:deny, retry_after}
    end
  end

  # Atomic counter update with default value creation
  defp update_counter(key, increment, expires_at) do
    :ets.update_counter(@table, key, increment, {key, 0, expires_at})
  end

  defp clean_expired_entries do
    now = System.system_time(:millisecond)
    match_spec = [{{{:_, :_}, :_, :"$1"}, [], [{:<, :"$1", {:const, now}}]}]

    try do
      :ets.select_delete(@table, match_spec)
    rescue
      ArgumentError -> 0
    end
  end

  defp schedule_cleanup(period) do
    Process.send_after(self(), :cleanup, period)
  end

  defp build_bucket_key(action, identifier) do
    "rate_limit:#{action}:#{identifier}"
  end
end
