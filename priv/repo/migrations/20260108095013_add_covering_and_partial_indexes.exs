defmodule Portfolio.Repo.Migrations.AddCoveringAndPartialIndexes do
  @moduledoc """
  Adds covering and partial indexes for query optimization.

  ## Covering Indexes

  Covering indexes include additional columns beyond the indexed ones,
  allowing PostgreSQL to satisfy queries directly from the index without
  accessing the table (index-only scans).

  ## Partial Indexes

  Partial indexes only index rows matching a condition, reducing index
  size and improving write performance for filtered queries.

  ## Performance Impact

  - `idx_albums_published_covering`: Optimizes public album listing queries
  - `idx_photos_processing_partial`: Optimizes admin dashboard processing status queries
  - `idx_photos_album_order`: Optimizes photo ordering within albums

  These indexes target the most frequent queries identified in the performance analysis.
  """

  use Ecto.Migration

  # Disable DDL transactions to allow CONCURRENTLY
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Covering index for published albums listing
    # Covers: SELECT title, slug, photo_count FROM albums WHERE published = true ORDER BY date_prise_vue DESC
    # PostgreSQL 11+ supports INCLUDE clause for covering indexes
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_albums_published_covering
    ON albums (published, date_prise_vue DESC)
    INCLUDE (title, slug)
    WHERE published = true
    """

    # Partial index for photos in processing state
    # Only indexes photos that are pending or processing (small subset)
    # Optimizes admin dashboard queries for processing status
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_photos_processing_partial
    ON photos (album_id, inserted_at DESC)
    WHERE processing_status IN ('pending', 'processing')
    """

    # Composite index for photo ordering within albums
    # Optimizes: SELECT * FROM photos WHERE album_id = ? ORDER BY display_order, inserted_at
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_photos_album_display_order
    ON photos (album_id, display_order, inserted_at DESC)
    """

    # Partial index for unpublished photos (admin queries)
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_photos_unpublished_partial
    ON photos (album_id, inserted_at DESC)
    WHERE published = false
    """
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_albums_published_covering"
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_photos_processing_partial"
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_photos_album_display_order"
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_photos_unpublished_partial"
  end
end
