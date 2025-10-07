defmodule Portfolio.Repo.Migrations.ConvertUserRolesToEnum do
  use Ecto.Migration

  def up do
    # Drop the old CHECK constraint
    execute "ALTER TABLE users DROP CONSTRAINT IF EXISTS valid_role"

    # Create the enum type
    execute """
    CREATE TYPE user_role AS ENUM ('admin', 'superadmin', 'user')
    """

    # Drop the default temporarily
    execute "ALTER TABLE users ALTER COLUMN role DROP DEFAULT"

    # Change the column type to use the enum with explicit casting
    execute """
    ALTER TABLE users
    ALTER COLUMN role TYPE user_role USING role::user_role
    """

    # Set the new default as enum value
    execute "ALTER TABLE users ALTER COLUMN role SET DEFAULT 'admin'::user_role"
  end

  def down do
    # Revert back to string
    alter table(:users) do
      modify :role, :string, from: :user_role, default: "admin"
    end

    # Drop the enum type
    execute "DROP TYPE user_role"
  end
end
