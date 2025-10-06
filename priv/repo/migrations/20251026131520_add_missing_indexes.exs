defmodule Portfolio.Repo.Migrations.AddMissingIndexes do
  @moduledoc """
  Optimizes existing indexes by converting them to partial indexes.

  ## Changes

  ### User Sessions table
  - Recreates `user_sessions_last_activity_at_index` as PARTIAL index
  - Only indexes active sessions (not deleted) to reduce index size
  - Improves cleanup query performance for expired sessions

  ### Magic Links table
  - Recreates `magic_links_expires_at_index` as PARTIAL index
  - Only indexes unused links to reduce index size
  - Improves cleanup query performance for expired links

  ## Performance Impact
  - Reduced index size (only relevant rows indexed)
  - Faster index scans for cleanup operations
  - Lower maintenance overhead (fewer rows to update)

  ## Note
  The albums indexes (slug, published_date) already exist and are optimal.
  """
  use Ecto.Migration

  def up do
    # Magic Links: Recreate as partial index to only index unused links
    drop_if_exists index(:magic_links, [:expires_at], name: :magic_links_expires_at_index)

    create index(:magic_links, [:expires_at],
             name: :magic_links_expires_at_index,
             where: "used_at IS NULL"
           )
  end

  def down do
    # Revert to full index
    drop_if_exists index(:magic_links, [:expires_at],
                     name: :magic_links_expires_at_index,
                     where: "used_at IS NULL"
                   )

    create index(:magic_links, [:expires_at], name: :magic_links_expires_at_index)
  end
end
