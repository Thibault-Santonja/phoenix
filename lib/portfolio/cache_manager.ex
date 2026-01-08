defmodule Portfolio.CacheManager do
  @moduledoc """
  Centralized cache management for the application.

  Provides a unified interface for cache operations, eliminating duplication
  across services and event handlers. Uses Cachex as the underlying cache.

  Implements the `Portfolio.Cache.CacheAdapter` behaviour.

  ## Design Principles

  1. **DRY**: Single implementation for cache operations
  2. **Consistency**: Uniform error handling and logging
  3. **Targeted Invalidation**: Prefer key-specific deletion over full cache clear

  ## Cache Namespaces

  The cache uses tuple keys for namespacing:
  - `{:session, token}` - Session data
  - `{:published_albums_by_year, preloads}` - Album listings
  - `{:user, user_id}` - User data

  ## Usage

      # Delete a single key
      CacheManager.delete({:session, token})

      # Delete multiple keys
      CacheManager.delete_many([{:session, token1}, {:session, token2}])

      # Invalidate all album-related cache
      CacheManager.invalidate_albums()

      # Invalidate session cache (handles both raw and hashed tokens)
      CacheManager.invalidate_session(token)
  """

  @behaviour Portfolio.Cache.CacheAdapter

  require Logger

  alias Portfolio.Auth.UserSession

  @cache_name :portfolio_cache

  # =============================================================================
  # Generic Cache Operations
  # =============================================================================

  @doc """
  Deletes a single key from the cache.

  ## Parameters

  - `key` - The cache key to delete

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> delete({:session, "abc123"})
      :ok
  """
  @impl Portfolio.Cache.CacheAdapter
  @spec delete(term()) :: :ok | {:error, boolean()}
  def delete(key) do
    case Cachex.del(@cache_name, key) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes multiple keys from the cache.

  Attempts to delete all keys, logging any failures.

  ## Parameters

  - `keys` - List of cache keys to delete

  ## Returns

  - `:ok` if all deletions succeeded
  - `{:error, errors}` if any deletion failed

  ## Examples

      iex> delete_many([{:session, "a"}, {:session, "b"}])
      :ok
  """
  @impl Portfolio.Cache.CacheAdapter
  @spec delete_many([term()]) :: :ok | {:error, [{term(), term()}]}
  def delete_many([]), do: :ok

  def delete_many(keys) when is_list(keys) do
    results =
      Enum.map(keys, fn key ->
        case delete(key) do
          :ok -> {:ok, key}
          {:error, reason} -> {:error, key, reason}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _, _}, &1))

    if errors == [] do
      :ok
    else
      error_tuples = Enum.map(errors, fn {:error, key, reason} -> {key, reason} end)
      Logger.warning("Cache deletion failures", errors: inspect(error_tuples))
      {:error, error_tuples}
    end
  end

  # =============================================================================
  # Session Cache Operations
  # =============================================================================

  @doc """
  Invalidates session cache by token.

  Handles both raw and hashed tokens by attempting deletion with both formats.
  This ensures cache consistency regardless of input format.

  ## Parameters

  - `token` - The session token (raw or hashed)

  ## Examples

      iex> invalidate_session("raw_token_value")
      :ok

      iex> invalidate_session("hashed_token_value")
      :ok
  """
  @impl Portfolio.Cache.CacheAdapter
  @spec invalidate_session(String.t()) :: :ok
  def invalidate_session(token) when is_binary(token) do
    # Hash the token for primary cache key
    hashed_token = UserSession.hash_token_value(token)

    # Delete both possible cache keys
    _ = delete({:session, hashed_token})
    _ = delete({:session, token})

    :ok
  end

  @doc """
  Invalidates session cache for multiple tokens.

  ## Parameters

  - `tokens` - List of session tokens to invalidate

  ## Examples

      iex> invalidate_sessions(["token1", "token2"])
      :ok
  """
  @impl Portfolio.Cache.CacheAdapter
  @spec invalidate_sessions([String.t()]) :: :ok
  def invalidate_sessions(tokens) when is_list(tokens) do
    Enum.each(tokens, &invalidate_session/1)
    :ok
  end

  # =============================================================================
  # Album Cache Operations
  # =============================================================================

  @doc """
  Invalidates all album-related cache entries.

  Targets specific cache keys used for album listings.
  Use this after album publication, unpublication, or deletion.

  ## Examples

      iex> invalidate_albums()
      :ok
  """
  @impl Portfolio.Cache.CacheAdapter
  @spec invalidate_albums() :: :ok
  def invalidate_albums do
    cache_keys = [
      {:published_albums_by_year, []},
      {:published_albums_by_year, [:photos]}
    ]

    case delete_many(cache_keys) do
      :ok ->
        Logger.debug("Albums cache invalidated (targeted keys)")
        :ok

      {:error, errors} ->
        Logger.warning("Partial album cache invalidation failure", errors: inspect(errors))
        :ok
    end
  end

  # =============================================================================
  # Fetch Operations
  # =============================================================================

  @doc """
  Fetches a value from cache, computing it if missing.

  This is a wrapper around `Cachex.fetch/4` with consistent error handling.

  ## Parameters

  - `key` - The cache key
  - `compute_fn` - Function to compute the value if not cached
  - `opts` - Options (`:ttl` for time-to-live in milliseconds)

  ## Returns

  The cached or computed value.

  ## Examples

      iex> fetch_or_compute({:user, id}, fn -> get_user(id) end, ttl: 60_000)
      %User{...}
  """
  @impl Portfolio.Cache.CacheAdapter
  @spec fetch_or_compute(term(), (-> term()), keyword()) :: term()
  def fetch_or_compute(key, compute_fn, opts \\ []) do
    ttl = Keyword.get(opts, :ttl)

    result =
      Cachex.fetch(@cache_name, key, fn ->
        value = compute_fn.()

        if ttl do
          {:commit, value, ttl: ttl}
        else
          {:commit, value}
        end
      end)

    case result do
      {:ok, value} -> value
      {:commit, value} -> value
      {:ignore, value} -> value
      {:error, _reason} -> compute_fn.()
    end
  end

  @doc """
  Raw fetch with full Cachex semantics for complex caching scenarios.

  Unlike `fetch_or_compute/3`, this function returns the raw Cachex result
  allowing callers to handle `:commit`, `:ignore`, and `:ok` differently.

  The compute function should return one of:
  - `{:commit, value}` - Cache the value
  - `{:commit, value, ttl: ms}` - Cache with TTL
  - `{:ignore, value}` - Return value without caching

  ## Parameters

  - `key` - The cache key
  - `compute_fn` - Function returning `{:commit, value}` or `{:ignore, value}`

  ## Returns

  - `{:ok, value}` - Value was already cached
  - `{:commit, value}` - Value was computed and cached
  - `{:ignore, value}` - Value was computed but not cached
  - `{:error, reason}` - Cache operation failed

  ## Examples

      iex> fetch({:mx, "example.com"}, fn ->
      ...>   case lookup_mx("example.com") do
      ...>     {:ok, records} -> {:commit, {:ok, records}, ttl: 3600_000}
      ...>     {:error, :timeout} -> {:ignore, {:error, :timeout}}
      ...>   end
      ...> end)
      {:commit, {:ok, [...]}}
  """
  @spec fetch(term(), (-> {:commit, term()} | {:commit, term(), keyword()} | {:ignore, term()})) ::
          {:ok, term()} | {:commit, term()} | {:ignore, term()} | {:error, term()}
  def fetch(key, compute_fn) do
    Cachex.fetch(@cache_name, key, compute_fn)
  end

  # =============================================================================
  # Low-Level Cache Operations
  # =============================================================================

  @doc """
  Gets a value from the cache.

  ## Parameters

  - `key` - The cache key

  ## Returns

  - `{:ok, value}` - Value found (nil if not present)
  - `{:error, reason}` - Cache operation failed
  """
  @spec get(term()) :: {:ok, term()} | {:error, term()}
  def get(key) do
    Cachex.get(@cache_name, key)
  end

  @doc """
  Puts a value in the cache with optional TTL.

  ## Parameters

  - `key` - The cache key
  - `value` - The value to cache
  - `opts` - Options (`:ttl` for time-to-live in milliseconds)

  ## Returns

  - `{:ok, true}` - Value was cached
  - `{:error, reason}` - Cache operation failed
  """
  @spec put(term(), term(), keyword()) :: {:ok, boolean()} | {:error, boolean()}
  def put(key, value, opts \\ []) do
    Cachex.put(@cache_name, key, value, opts)
  end

  @doc """
  Increments a numeric value in the cache.

  ## Parameters

  - `key` - The cache key
  - `amount` - Amount to increment (default: 1)

  ## Returns

  - `{:ok, new_value}` - New value after increment
  - `{:error, reason}` - Cache operation failed
  """
  @spec incr(term(), integer()) :: {:ok, integer()} | {:error, integer()}
  def incr(key, amount \\ 1) do
    Cachex.incr(@cache_name, key, amount)
  end
end
