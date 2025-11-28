defmodule Portfolio.Repo.Migrations.RemoveCoverPhotoIdFromAlbums do
  use Ecto.Migration

  def change do
    alter table(:albums) do
      remove :cover_photo_id, references(:photos, on_delete: :nilify_all)
    end
  end
end
