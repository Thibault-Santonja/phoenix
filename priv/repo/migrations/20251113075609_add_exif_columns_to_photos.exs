defmodule Portfolio.Repo.Migrations.AddExifColumnsToPhotos do
  @moduledoc """
  Adds specific EXIF columns to photos table for efficient querying.

  According to ADR-011 Phase 3, we extract key EXIF metadata to dedicated
  columns for:
  - Timeline chronological display (captured_at)
  - Equipment display (camera, lens, iso, aperture, focal_length)
  - GPS data storage (not publicly exposed, admin only)

  The existing exif_data JSONB field is kept for additional metadata.
  """
  use Ecto.Migration

  def change do
    alter table(:photos) do
      # Date and time when photo was taken (from EXIF DateTimeOriginal)
      add :captured_at, :utc_datetime

      # Camera equipment
      add :camera, :string
      add :lens, :string

      # Camera settings
      add :iso, :integer
      add :aperture, :string
      add :focal_length, :string
      add :shutter_speed, :string

      # GPS coordinates (stored but not publicly exposed)
      add :gps_latitude, :float
      add :gps_longitude, :float
    end

    # Index on captured_at for timeline chronological sorting
    create index(:photos, [:captured_at])

    # Index on camera for filtering by equipment
    create index(:photos, [:camera])
  end
end
