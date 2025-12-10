defmodule Portfolio.Repo.Migrations.AddLastAdminProtectionTrigger do
  @moduledoc """
  Adds a database-level safeguard to prevent deletion of the last admin user.

  This complements the application-level protection in UserService.delete_user/1
  and guards against race conditions (e.g., two parallel delete attempts).

  See ADR-021 for RBAC design decisions.
  """
  use Ecto.Migration

  def up do
    # Create a function that prevents deletion of the last admin
    execute """
    CREATE OR REPLACE FUNCTION prevent_last_admin_deletion()
    RETURNS TRIGGER AS $$
    DECLARE
      admin_count INTEGER;
    BEGIN
      -- Only check if deleting an admin user
      IF OLD.role = 'admin' THEN
        -- Count remaining admins (excluding the one being deleted)
        SELECT COUNT(*) INTO admin_count
        FROM users
        WHERE role = 'admin' AND id != OLD.id;

        IF admin_count = 0 THEN
          RAISE EXCEPTION 'Cannot delete the last admin user'
            USING ERRCODE = 'P0001';
        END IF;
      END IF;

      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Create the trigger
    execute """
    CREATE TRIGGER protect_last_admin
    BEFORE DELETE ON users
    FOR EACH ROW
    EXECUTE FUNCTION prevent_last_admin_deletion();
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS protect_last_admin ON users;"
    execute "DROP FUNCTION IF EXISTS prevent_last_admin_deletion();"
  end
end
