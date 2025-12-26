defmodule Portfolio.Cache.CacheAdapter do
  @moduledoc """
  Behaviour for cache adapters.

  Defines the contract for cache operations, allowing different
  implementations (ETS, Redis, Memcached, etc.) to be swapped
  without changing business logic.

  ## Implementations

  - `Portfolio.CacheManager` - Default Cachex-based implementation

  ## Configuration

  Configure the adapter in your config:

      config :portfolio, :cache_adapter, Portfolio.CacheManager

  ## Usage

      adapter = Application.get_env(:portfolio, :cache_adapter, Portfolio.CacheManager)
      adapter.fetch_or_compute({:user, id}, fn -> get_user(id) end, ttl: 60_000)

  """

  @doc """
  Deletes a single key from the cache.

  ## Parameters

  - `key` - The cache key to delete

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure

  """
  @callback delete(key :: term()) :: :ok | {:error, term()}

  @doc """
  Deletes multiple keys from the cache.

  ## Parameters

  - `keys` - List of cache keys to delete

  ## Returns

  - `:ok` if all deletions succeeded
  - `{:error, errors}` if any deletion failed

  """
  @callback delete_many(keys :: [term()]) :: :ok | {:error, [{term(), term()}]}

  @doc """
  Invalidates session cache by token.

  Handles both raw and hashed tokens.

  ## Parameters

  - `token` - The session token (raw or hashed)

  """
  @callback invalidate_session(token :: String.t()) :: :ok

  @doc """
  Invalidates session cache for multiple tokens.

  ## Parameters

  - `tokens` - List of session tokens to invalidate

  """
  @callback invalidate_sessions(tokens :: [String.t()]) :: :ok

  @doc """
  Invalidates all album-related cache entries.

  """
  @callback invalidate_albums() :: :ok

  @doc """
  Fetches a value from cache, computing it if missing.

  ## Parameters

  - `key` - The cache key
  - `compute_fn` - Function to compute the value if not cached
  - `opts` - Options (`:ttl` for time-to-live in milliseconds)

  ## Returns

  The cached or computed value.

  """
  @callback fetch_or_compute(key :: term(), compute_fn :: (-> term()), opts :: keyword()) ::
              term()
end
