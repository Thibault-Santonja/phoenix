defmodule Portfolio.Cache do
  @moduledoc """
  Cache facade providing a unified interface for caching operations.

  This module delegates to the configured cache strategy, allowing
  different implementations for different environments:

  - Production: `CachexStrategy` (full caching with Cachex)
  - Test: `NoOpStrategy` (bypasses cache to prevent test pollution)

  ## Configuration

      # config/config.exs
      config :portfolio, :cache_strategy, Portfolio.Cache.CachexStrategy

      # config/test.exs
      config :portfolio, :cache_strategy, Portfolio.Cache.NoOpStrategy

  ## Usage

      # Fetch with computation fallback
      Portfolio.Cache.fetch(:my_key, fn -> expensive_computation() end)

      # Fetch with TTL
      Portfolio.Cache.fetch(:my_key, fn -> data() end, ttl: :timer.minutes(5))

      # Invalidate specific key
      Portfolio.Cache.invalidate(:my_key)

      # Clear all cache
      Portfolio.Cache.clear_all()
  """

  @doc """
  Fetches a value from cache, computing it if not present.

  ## Parameters

  - `key` - Cache key
  - `compute_fn` - Function to compute value if not cached
  - `opts` - Options:
    - `:ttl` - Time to live in milliseconds

  ## Examples

      iex> Portfolio.Cache.fetch(:user_count, fn -> count_users() end)
      42

      iex> Portfolio.Cache.fetch(:stats, fn -> compute_stats() end, ttl: 60_000)
      %{total: 100}
  """
  @spec fetch(term(), (-> term()), keyword()) :: term()
  def fetch(key, compute_fn, opts \\ []) do
    strategy().fetch(key, compute_fn, opts)
  end

  @doc """
  Invalidates a cache entry.

  ## Examples

      iex> Portfolio.Cache.invalidate(:user_count)
      :ok
  """
  @spec invalidate(term()) :: :ok
  def invalidate(key) do
    strategy().invalidate(key)
  end

  @doc """
  Clears all cache entries.

  ## Examples

      iex> Portfolio.Cache.clear_all()
      :ok
  """
  @spec clear_all() :: :ok
  def clear_all do
    strategy().clear_all()
  end

  # Returns the configured cache strategy module
  @spec strategy() :: module()
  defp strategy do
    Application.get_env(:portfolio, :cache_strategy, Portfolio.Cache.CachexStrategy)
  end
end
