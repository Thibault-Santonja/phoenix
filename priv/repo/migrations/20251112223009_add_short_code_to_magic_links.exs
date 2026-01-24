defmodule Portfolio.Repo.Migrations.AddShortCodeToMagicLinks do
  use Ecto.Migration

  def change do
    alter table(:magic_links) do
      add :short_code, :string, size: 6
    end

    create unique_index(:magic_links, [:short_code])
  end
end
