defmodule Portfolio.Repo.Migrations.RemoveCoverPhotoIdFromAlbums do
  use Ecto.Migration

  def up do
    alter table(:albums) do
      remove_if_exists :cover_photo_id, :binary_id
    end
  end

  def down do
    alter table(:albums) do
      add_if_not_exists :cover_photo_id, :binary_id
    end
  end
end
