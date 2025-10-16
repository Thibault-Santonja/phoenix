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

  @type action :: :magic_link_request | :magic_link_verify | :login_attempt
  @type rate_identifier :: String.t()
  @type result :: {:allow, remaining :: integer()} | {:deny, retry_after :: integer()}

  # Rate limit configurations (limit, period in milliseconds)
  @rate_limits %{
    # 5 magic link requests per hour per email
    magic_link_request: {5, :timer.hours(1)},
    # 10 magic link verification attempts per 5 minutes per IP (prevents brute force)
    magic_link_verify: {10, :timer.minutes(5)},
    # 10 login attempts per hour per IP
    login_attempt: {10, :timer.hours(1)}
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
  @spec check_rate(action(), rate_identifier()) :: result()
  def check_rate(action, identifier) when is_atom(action) and is_binary(identifier) do
    {limit, period} = Map.fetch!(@rate_limits, action)
    bucket_key = build_bucket_key(action, identifier)

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
    Hammer.delete_buckets(bucket_key)
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
