defmodule Portfolio.Cache.NoOpStrategy do
  @moduledoc """
  No-operation cache strategy for testing.

  This strategy bypasses the cache entirely, always computing values fresh.
  Used in test environments to prevent cache pollution between tests.
  """

  @behaviour Portfolio.Cache.CacheStrategy

  @impl true
  def fetch(_key, compute_fn, _opts \\ []) do
    compute_fn.()
  end

  @impl true
  def invalidate(_key) do
    :ok
  end

  @impl true
  def clear_all do
    :ok
  end
end
