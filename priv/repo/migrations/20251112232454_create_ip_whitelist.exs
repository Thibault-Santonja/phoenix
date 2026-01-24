defmodule Portfolio.Repo.Migrations.CreateIpWhitelist do
  use Ecto.Migration

  def change do
    create table(:ip_whitelist, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ip_address, :string, null: false
      add :description, :string
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(updated_at: false)
    end

    create unique_index(:ip_whitelist, [:ip_address])
    create index(:ip_whitelist, [:created_by_id])
  end
end
