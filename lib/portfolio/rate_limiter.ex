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

  @type action :: :magic_link_request | :login_attempt
  @type rate_identifier :: String.t()
  @type result :: {:allow, remaining :: integer()} | {:deny, retry_after :: integer()}

  # Rate limit configurations (limit, period in milliseconds)
  @rate_limits %{
    # 5 magic link requests per hour per email
    magic_link_request: {5, :timer.hours(1)},
    # 10 login attempts per hour per IP
    login_attempt: {10, :timer.hours(1)}
  }

  @doc """
  Vérifie si une action est autorisée pour un identifiant donné.

  ## Paramètres

  - `action` - Type d'action à limiter (atom)
  - `identifier` - Identifiant unique (email, IP, user_id, etc.)

  ## Retour

  - `{:allow, remaining}` - Action autorisée, nombre de requêtes restantes
  - `{:deny, retry_after}` - Action refusée, temps d'attente en ms

  ## Exemples

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
  Réinitialise le compteur pour une action et un identifiant donnés.

  Utile pour les tests ou pour réinitialiser manuellement un rate limit.

  ## Exemples

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
  Retourne les limites configurées pour une action.

  ## Exemples

      iex> get_limit(:magic_link_request)
      {5, 3600000}  # 5 requests per hour
  """
  @spec get_limit(action()) :: {integer(), integer()}
  def get_limit(action) when is_atom(action) do
    Map.fetch!(@rate_limits, action)
  end

  # Construit une clé unique pour le bucket Hammer
  @spec build_bucket_key(action(), rate_identifier()) :: String.t()
  defp build_bucket_key(action, identifier) do
    "rate_limit:#{action}:#{identifier}"
  end
end
