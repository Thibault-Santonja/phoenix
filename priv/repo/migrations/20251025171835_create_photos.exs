defmodule Portfolio.Repo.Migrations.CreatePhotos do
  use Ecto.Migration

  def change do
    create table(:photos, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:album_id, references(:albums, type: :binary_id, on_delete: :delete_all), null: false)
      add(:title, :string)
      add(:description, :text)
      add(:slug, :string)
      add(:display_order, :integer, default: 0, null: false)
      add(:taken_at, :date)
      add(:published, :boolean, default: true, null: false)
      add(:original_filename, :string, null: false)
      add(:file_path, :string, null: false)
      add(:hash, :string)
      add(:mime_type, :string)
      add(:exif_data, :map, default: %{})

      timestamps(type: :utc_datetime)
    end

    # Indexes pour performance
    create(index(:photos, [:album_id, :display_order]))
    create(index(:photos, [:published]))
    create(unique_index(:photos, [:hash]))
    create(unique_index(:photos, [:album_id, :slug]))

    # Contrainte de validation
    create(constraint(:photos, :display_order_must_be_positive, check: "display_order >= 0"))
  end
end
