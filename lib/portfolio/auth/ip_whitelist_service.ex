defmodule Portfolio.Auth.IPWhitelistService do
  @moduledoc """
  Service for managing the IP address whitelist.

  Whitelisted IPs are not subject to rate limiting and can
  freely access protected resources.

  ## Cache

  The service uses an ETS cache to improve verification performance.
  The cache is automatically updated when entries are added/removed.

  ## Usage

      # Add an IP
      IPWhitelistService.add_to_whitelist(%{
        ip_address: "192.168.1.100",
        description: "Office"
      }, admin_id)

      # Check if an IP is whitelisted
      IPWhitelistService.whitelisted?("192.168.1.100")
      #=> true

      # Remove an IP
      IPWhitelistService.remove_from_whitelist(entry_id)
  """

  require Logger

  alias Portfolio.Auth.IPWhitelist
  alias Portfolio.Auth.Repositories.IPWhitelistRepository

  @cache_table :ip_whitelist_cache
  @cache_ttl :timer.minutes(5)

  @doc """
  Initializes the ETS cache at application startup.

  Should be called in Application.start/2.
  """
  def init_cache do
    # Create the table only if it doesn't exist
    case :ets.whereis(@cache_table) do
      :undefined ->
        _ = :ets.new(@cache_table, [:set, :public, :named_table, read_concurrency: true])
        :ok

      _tid ->
        # Table already exists, just clear the cache for testing
        _ = :ets.delete_all_objects(@cache_table)
        :ok
    end

    # Only auto-refresh from database in non-test environments
    # In test, the cache starts empty and tests populate it as needed
    if Application.get_env(:portfolio, :auto_refresh_ip_whitelist, true) do
      refresh_cache()
    end

    :ok
  end

  @doc """
  Lists all whitelist entries.

  ## Examples

      iex> list_whitelist()
      [%IPWhitelist{}, ...]
  """
  @spec list_whitelist() :: [IPWhitelist.t()]
  def list_whitelist do
    IPWhitelistRepository.list_all()
  end

  @doc """
  Adds an IP address to the whitelist.

  ## Parameters

  - `attrs` - Map containing `:ip_address` (required) and `:description` (optional)
  - `created_by_id` - ID of the user creating the entry

  ## Examples

      iex> add_to_whitelist(%{ip_address: "192.168.1.100"}, admin_id)
      {:ok, %IPWhitelist{}}

      iex> add_to_whitelist(%{ip_address: "invalid"}, admin_id)
      {:error, %Ecto.Changeset{}}
  """
  @spec add_to_whitelist(map(), Ecto.UUID.t()) ::
          {:ok, IPWhitelist.t()} | {:error, Ecto.Changeset.t()}
  def add_to_whitelist(attrs, created_by_id) do
    # Ensure string keys for Ecto.Changeset.cast/3
    attrs =
      attrs
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Map.new()
      |> Map.put("created_by_id", created_by_id)

    # Optimistic cache update: add IP to cache BEFORE DB insert
    # This prevents race condition where requests arrive between DB commit and cache refresh
    ip_address = attrs["ip_address"]
    add_to_cache_optimistically(ip_address)

    case IPWhitelistRepository.insert(attrs) do
      {:ok, entry} ->
        Logger.info("IP added to whitelist",
          ip: entry.ip_address,
          created_by_id: created_by_id
        )

        # Full refresh to ensure consistency (removes optimistic entry if needed)
        refresh_cache()
        {:ok, entry}

      {:error, changeset} ->
        # Rollback optimistic cache update on failure
        remove_from_cache_optimistically(ip_address)
        {:error, changeset}
    end
  end

  # Adds IP to cache optimistically before DB insert
  @spec add_to_cache_optimistically(String.t() | nil) :: :ok
  defp add_to_cache_optimistically(nil), do: :ok

  defp add_to_cache_optimistically(ip_address) when is_binary(ip_address) do
    if :ets.whereis(@cache_table) != :undefined do
      case :ets.lookup(@cache_table, :whitelist) do
        [{:whitelist, ips, expires_at}] ->
          new_ips = MapSet.put(ips, ip_address)
          :ets.insert(@cache_table, {:whitelist, new_ips, expires_at})

        [] ->
          # Cache empty, create with just this IP
          expires_at = System.system_time(:millisecond) + @cache_ttl
          :ets.insert(@cache_table, {:whitelist, MapSet.new([ip_address]), expires_at})
      end
    end

    :ok
  end

  # Removes IP from cache if DB insert failed (rollback optimistic update)
  @spec remove_from_cache_optimistically(String.t() | nil) :: :ok
  defp remove_from_cache_optimistically(nil), do: :ok

  defp remove_from_cache_optimistically(ip_address) when is_binary(ip_address) do
    if :ets.whereis(@cache_table) != :undefined do
      case :ets.lookup(@cache_table, :whitelist) do
        [{:whitelist, ips, expires_at}] ->
          new_ips = MapSet.delete(ips, ip_address)
          :ets.insert(@cache_table, {:whitelist, new_ips, expires_at})

        [] ->
          :ok
      end
    end

    :ok
  end

  @doc """
  Removes an entry from the whitelist.

  ## Examples

      iex> remove_from_whitelist(entry_id)
      {:ok, %IPWhitelist{}}

      iex> remove_from_whitelist(non_existent_id)
      {:error, :not_found}
  """
  @spec remove_from_whitelist(Ecto.UUID.t()) ::
          {:ok, IPWhitelist.t()} | {:error, :not_found}
  def remove_from_whitelist(id) do
    case IPWhitelistRepository.get(id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, entry} ->
        {:ok, deleted} = IPWhitelistRepository.delete(entry)

        Logger.info("IP removed from whitelist",
          ip: deleted.ip_address
        )

        refresh_cache()
        {:ok, deleted}
    end
  end

  @doc """
  Retrieves a whitelist entry by its ID.

  ## Examples

      iex> get_whitelist_entry(id)
      %IPWhitelist{}

      iex> get_whitelist_entry(non_existent_id)
      nil
  """
  @spec get_whitelist_entry(Ecto.UUID.t()) :: IPWhitelist.t() | nil
  def get_whitelist_entry(id) do
    case IPWhitelistRepository.get(id) do
      {:ok, entry} -> entry
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Updates a whitelist entry (description only).

  ## Examples

      iex> update_whitelist_entry(entry, %{description: "New description"})
      {:ok, %IPWhitelist{}}
  """
  @spec update_whitelist_entry(IPWhitelist.t(), map()) ::
          {:ok, IPWhitelist.t()} | {:error, Ecto.Changeset.t()}
  def update_whitelist_entry(entry, attrs) do
    IPWhitelistRepository.update(entry, attrs)
  end

  @doc """
  Checks if an IP address is whitelisted.

  Uses an ETS cache for optimal performance.

  ## Examples

      iex> whitelisted?("192.168.1.100")
      true

      iex> whitelisted?("10.0.0.1")
      false
  """
  @spec whitelisted?(String.t()) :: boolean()
  def whitelisted?(ip_address) when is_binary(ip_address) do
    if :ets.whereis(@cache_table) == :undefined do
      false
    else
      check_cache(ip_address)
    end
  end

  # Overload for IP tuples - converts to string then checks
  @spec whitelisted?(:inet.ip_address()) :: boolean()
  def whitelisted?(ip_tuple) when is_tuple(ip_tuple) do
    ip_string = ip_tuple_to_string(ip_tuple)
    whitelisted?(ip_string)
  end

  # Check cache for IP address
  defp check_cache(ip_address) do
    case :ets.lookup(@cache_table, :whitelist) do
      [{:whitelist, ips, _expires_at}] ->
        MapSet.member?(ips, ip_address)

      [] ->
        handle_cache_miss(ip_address)
    end
  end

  # Cache miss - refresh if auto-refresh is enabled
  # Returns result directly without recursion to avoid stack depth issues
  defp handle_cache_miss(ip_address) do
    if Application.get_env(:portfolio, :auto_refresh_ip_whitelist, true) do
      refresh_cache()

      # Check directly in cache after refresh (no recursion)
      case :ets.lookup(@cache_table, :whitelist) do
        [{:whitelist, ips, _expires_at}] -> MapSet.member?(ips, ip_address)
        [] -> false
      end
    else
      # In test environment, cache is not auto-refreshed
      false
    end
  end

  # Refreshes the cache from the database
  @spec refresh_cache() :: :ok
  defp refresh_cache do
    ips =
      IPWhitelistRepository.list_ip_addresses()
      |> MapSet.new()

    expires_at = System.system_time(:millisecond) + @cache_ttl

    :ets.insert(@cache_table, {:whitelist, ips, expires_at})

    Logger.debug("IP whitelist cache refreshed", count: MapSet.size(ips))

    :ok
  end

  # Converts an IP tuple to string
  @spec ip_tuple_to_string(:inet.ip_address()) :: String.t()
  defp ip_tuple_to_string(ip_tuple) do
    case :inet.ntoa(ip_tuple) do
      {:error, _} -> ""
      charlist -> List.to_string(charlist)
    end
  end
end
