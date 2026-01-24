defmodule Portfolio.Cache.CacheStrategy do
  @moduledoc """
  Behavior defining the cache strategy interface.

  This abstraction allows different cache implementations:
  - `CachexStrategy` for production (uses Cachex)
  - `NoOpStrategy` for tests (bypasses cache entirely)

  ## Usage

  The strategy is configured via application config:

      # config/config.exs (default)
      config :portfolio, :cache_strategy, Portfolio.Cache.CachexStrategy

      # config/test.exs
      config :portfolio, :cache_strategy, Portfolio.Cache.NoOpStrategy

  Services should use `Portfolio.Cache.fetch/3` instead of calling
  Cachex directly:

      defmodule MyService do
        alias Portfolio.Cache

        def get_data do
          Cache.fetch(:my_key, fn -> expensive_computation() end, ttl: :timer.minutes(5))
        end
      end

  ## Benefits

  - **Testability**: Tests run without cache pollution
  - **SOLID**: Open/Closed principle - add new strategies without modifying existing code
  - **DRY**: Cache logic centralized, not duplicated with `if Mix.env() == :test`
  """

  @doc """
  Fetches a value from cache, computing it if not present.

  ## Parameters

  - `key` - Cache key (atom or string)
  - `compute_fn` - Function to compute value if not cached
  - `opts` - Options:
    - `:ttl` - Time to live in milliseconds (optional)

  ## Returns

  The cached or computed value.
  """
  @callback fetch(key :: term(), compute_fn :: (-> term()), opts :: keyword()) :: term()

  @doc """
  Invalidates a cache entry.

  ## Parameters

  - `key` - Cache key to invalidate

  ## Returns

  `:ok`
  """
  @callback invalidate(key :: term()) :: :ok

  @doc """
  Clears all cache entries.

  ## Returns

  `:ok`
  """
  @callback clear_all() :: :ok
end
