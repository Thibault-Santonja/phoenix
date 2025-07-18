defmodule Portfolio.Repo.Migrations.AddDateFinToAlbums do
  use Ecto.Migration

  def change do
    alter table(:albums) do
      add :date_fin_prise_vue, :date, null: true
    end
  end
end
