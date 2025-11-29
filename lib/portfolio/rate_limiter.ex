defmodule Portfolio.RateLimiter do
  @moduledoc """
  Rate limiting using Hammer.

  Provides rate limiting for various operations to prevent abuse:
  - Magic link requests (email-based authentication)
  - Login attempts
  - API endpoints

  ## Configuration

  Rate limits are defined per action:

  - `:magic_link_request` - 5 requests per hour per email
  - `:login_attempt` - 10 attempts per hour per IP

  ## Exemples

      iex> RateLimiter.check_rate(:magic_link_request, "user@example.com")
      {:allow, 4}  # 4 requests remaining

      iex> RateLimiter.check_rate(:magic_link_request, "spammer@example.com")
      {:deny, 0}  # Rate limit exceeded
  """

  require Logger

  @type action :: :magic_link_request | :magic_link_verify | :login_attempt | :session_creation
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
    session_creation: {20, :timer.hours(1)}
  }

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

    result =
      case Hammer.check_rate(bucket_key, period, limit) do
        {:allow, count} ->
          remaining = limit - count

          Logger.debug("Rate limit check passed",
            action: action,
            identifier: identifier,
            remaining: remaining
          )

          {:allow, remaining}

        {:deny, _limit} ->
          # Calculate retry_after based on the oldest entry in the bucket
          retry_after = period

          Logger.warning("Rate limit exceeded",
            action: action,
            identifier: identifier,
            retry_after_ms: retry_after
          )

          {:deny, retry_after}
      end

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
    _result = Hammer.delete_buckets(bucket_key)
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
    # Clear all Hammer ETS buckets by deleting all objects from all Hammer tables
    # Hammer.Backend.ETS uses multiple ETS tables, we need to clear them all
    try do
      # List all ETS tables and find Hammer tables
      :ets.all()
      |> Enum.filter(fn table ->
        try do
          info = :ets.info(table)
          name = Keyword.get(info, :name, "")
          name == Hammer.ETS or String.contains?(to_string(name), "hammer")
        rescue
          _ -> false
        end
      end)
      |> Enum.each(fn table ->
        try do
          :ets.delete_all_objects(table)
        rescue
          _ -> :ok
        end
      end)
    rescue
      _ -> :ok
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
      :ets.all()
      |> Enum.filter(fn table ->
        try do
          info = :ets.info(table)
          name = Keyword.get(info, :name, "")
          name == Hammer.ETS or String.contains?(to_string(name), "hammer")
        rescue
          _ -> false
        end
      end)
      |> Enum.each(fn table ->
        try do
          # Get all objects and filter by action
          :ets.tab2list(table)
          |> Enum.each(fn {key, _value} ->
            # Keys are like: "rate_limit:magic_link_request:user@example.com"
            key_str = to_string(key)

            should_delete =
              Enum.any?(actions, fn action ->
                String.contains?(key_str, "rate_limit:#{action}:")
              end)

            if should_delete do
              :ets.delete(table, key)
            end
          end)
        rescue
          _ -> :ok
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
      :ets.all()
      |> Enum.filter(fn table ->
        try do
          info = :ets.info(table)
          name = Keyword.get(info, :name, "")
          name == Hammer.ETS or String.contains?(to_string(name), "hammer")
        rescue
          _ -> false
        end
      end)
      |> Enum.each(fn table ->
        try do
          # Get all objects and filter by action
          :ets.tab2list(table)
          |> Enum.each(fn {key, _value} ->
            # Keys are like: "rate_limit:magic_link_request:user@example.com"
            key_str = to_string(key)

            should_keep =
              Enum.any?(actions, fn action ->
                String.contains?(key_str, "rate_limit:#{action}:")
              end)

            if not should_keep do
              :ets.delete(table, key)
            end
          end)
        rescue
          _ -> :ok
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

  # Build a unique key for the Hammer bucket
  @spec build_bucket_key(action(), rate_identifier()) :: String.t()
  defp build_bucket_key(action, identifier) do
    "rate_limit:#{action}:#{identifier}"
  end
end
