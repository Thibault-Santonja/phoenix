defmodule Portfolio.Config.CacheConfig do
  @moduledoc """
  Centralized cache configuration.

  This module provides a single source of truth for all cache-related
  configuration values, including TTLs and cache keys.

  ## Cache Keys

  All cache keys used in the application are defined here to prevent
  typos and ensure consistency across modules.

  ## TTL Values

  Default TTL values are defined here but can be overridden via
  application configuration for different environments.

  ## Usage

      # Get session cache TTL
      CacheConfig.session_ttl()

      # Get cache key for published albums
      CacheConfig.published_albums_key(preloads: [:photos])
  """

  # =============================================================================
  # TTL Configuration
  # =============================================================================

  @doc """
  Returns the TTL for session cache entries.

  Default: 1 hour. Can be overridden via config :portfolio, :cache, :session_ttl
  """
  @spec session_ttl() :: non_neg_integer()
  def session_ttl do
    get_config(:session_ttl, :timer.hours(1))
  end

  @doc """
  Returns the TTL for published albums cache.

  Default: 1 hour. Can be overridden via config :portfolio, :cache, :albums_ttl
  """
  @spec albums_ttl() :: non_neg_integer()
  def albums_ttl do
    get_config(:albums_ttl, :timer.hours(1))
  end

  @doc """
  Returns the TTL for MX validation cache.

  Default: 1 hour. Can be overridden via config :portfolio, :cache, :mx_validation_ttl
  """
  @spec mx_validation_ttl() :: non_neg_integer()
  def mx_validation_ttl do
    get_config(:mx_validation_ttl, :timer.hours(1))
  end

  # =============================================================================
  # Cache Keys
  # =============================================================================

  @doc """
  Returns the cache key for published albums grouped by year.

  ## Parameters

  - `opts` - Options keyword list
    - `:preloads` - List of preloaded associations (default: [])

  ## Examples

      iex> CacheConfig.published_albums_key()
      {:published_albums_by_year, []}

      iex> CacheConfig.published_albums_key(preloads: [:photos])
      {:published_albums_by_year, [:photos]}
  """
  @spec published_albums_key(keyword()) :: {atom(), list()}
  def published_albums_key(opts \\ []) do
    preloads = Keyword.get(opts, :preloads, [])
    {:published_albums_by_year, preloads}
  end

  @doc """
  Returns the cache key for a user session.

  ## Parameters

  - `hashed_token` - The hashed session token

  ## Examples

      iex> CacheConfig.session_key("abc123hash")
      {:session, "abc123hash"}
  """
  @spec session_key(String.t()) :: {atom(), String.t()}
  def session_key(hashed_token) do
    {:session, hashed_token}
  end

  @doc """
  Returns the cache key for MX record validation.

  ## Parameters

  - `domain` - The email domain to validate

  ## Examples

      iex> CacheConfig.mx_validation_key("example.com")
      {:mx_validation, "example.com"}
  """
  @spec mx_validation_key(String.t()) :: {atom(), String.t()}
  def mx_validation_key(domain) do
    {:mx_validation, domain}
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp get_config(key, default) do
    :portfolio
    |> Application.get_env(:cache, [])
    |> Keyword.get(key, default)
  end
end
