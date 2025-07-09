defmodule Portfolio.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS citext", "")

    # Table users pour l'authentification admin
    create table(:users, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:email, :citext, null: false)
      add(:name, :string)
      add(:role, :string, null: false, default: "admin")

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:users, [:email]))
    create(constraint(:users, :valid_role, check: "role IN ('admin', 'superadmin')"))

    # Table magic_links pour l'authentification passwordless
    create table(:magic_links, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:token, :string, null: false)
      add(:expires_at, :utc_datetime, null: false)
      add(:used_at, :utc_datetime)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create(index(:magic_links, [:user_id]))
    create(unique_index(:magic_links, [:token]))
    create(index(:magic_links, [:expires_at]))
  end
end
