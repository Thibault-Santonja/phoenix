defmodule Portfolio.Repo.Migrations.AddIpWhitelistIndex do
  use Ecto.Migration

  @moduledoc """
  Adds index on ip_whitelist.ip_address for faster lookups.

  The ip_whitelist table is queried on every rate-limited request to check
  if the client IP is whitelisted. Without an index, this requires a
  sequential scan of the table.

  ## Performance Impact

  Before: O(n) sequential scan on every rate-limited request
  After: O(log n) index lookup

  ## Concurrent Index Creation

  Uses CREATE INDEX CONCURRENTLY to avoid locking the table during
  index creation in production.
  """

  # Disable DDL transaction for concurrent index creation
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Index on ip_address for fast whitelist lookups
    create_if_not_exists index(:ip_whitelist, [:ip_address], concurrently: true)
  end
end
