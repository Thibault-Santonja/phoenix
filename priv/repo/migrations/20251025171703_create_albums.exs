defmodule Portfolio.Repo.Migrations.CreateAlbums do
  use Ecto.Migration

  def change do
    create table(:albums, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :slug, :string, null: false
      add :type, :string, null: false
      add :description, :text
      add :location, :string
      add :date_prise_vue, :date, null: false
      add :published, :boolean, default: false, null: false
      add :reference_link, :string
      add :cover_photo_id, :binary_id
      add :exif_data, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    # Indexes pour performance
    create unique_index(:albums, [:slug])
    create index(:albums, [:type])
    create index(:albums, [:published, :date_prise_vue])
  end
end
