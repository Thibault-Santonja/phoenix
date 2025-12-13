defmodule Portfolio.Repo.Migrations.AddAuthPerformanceIndexes do
  @moduledoc """
  Adds performance indexes for authentication-related tables.

  These indexes optimize the most frequently queried columns:
  - Magic link token lookups (every magic link verification)
  - Magic link short code lookups (email display)
  - Session token lookups (every authenticated request)

  Impact: Reduces query time from O(n) table scan to O(log n) index lookup.
  """
  use Ecto.Migration

  def change do
    # Magic links - token is queried on every verification attempt
    create_if_not_exists unique_index(:magic_links, [:token])

    # Magic links - short_code is used for email display and verification
    create_if_not_exists unique_index(:magic_links, [:short_code])

    # User sessions - token is queried on every authenticated request
    create_if_not_exists unique_index(:user_sessions, [:token])

    # User sessions - user_id for listing user's sessions (admin, logout all)
    create_if_not_exists index(:user_sessions, [:user_id])

    # Magic links - user_id for listing user's magic links
    create_if_not_exists index(:magic_links, [:user_id])

    # Magic links - expires_at for cleanup jobs
    create_if_not_exists index(:magic_links, [:expires_at])
  end
end
