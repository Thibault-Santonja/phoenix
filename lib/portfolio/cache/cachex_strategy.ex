defmodule Portfolio.Cache.CachexStrategy do
  @moduledoc """
  Production cache strategy using Cachex.

  This strategy provides full caching functionality for production environments.
  """

  @behaviour Portfolio.Cache.CacheStrategy

  @cache_name :portfolio_cache

  @impl true
  def fetch(key, compute_fn, opts \\ []) do
    ttl = Keyword.get(opts, :ttl)
    cachex_fn = build_cachex_fn(compute_fn, ttl)

    case Cachex.fetch(@cache_name, key, cachex_fn) do
      {:ok, value} -> value
      {:commit, value} -> value
      {:ignore, value} -> value
      {:error, _reason} -> compute_fn.()
    end
  end

  @impl true
  def invalidate(key) do
    _ = Cachex.del(@cache_name, key)
    :ok
  end

  @impl true
  def clear_all do
    _ = Cachex.clear(@cache_name)
    :ok
  end

  defp build_cachex_fn(compute_fn, nil) do
    fn -> {:commit, compute_fn.()} end
  end

  defp build_cachex_fn(compute_fn, ttl) do
    fn -> {:commit, compute_fn.(), ttl: ttl} end
  end
end
