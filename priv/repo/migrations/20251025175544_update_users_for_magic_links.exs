defmodule Portfolio.Repo.Migrations.UpdateUsersForMagicLinks do
  use Ecto.Migration

  def change do
    # Modifier la table users pour magic links
    alter table(:users) do
      add_if_not_exists(:name, :string)
      add_if_not_exists(:role, :string, default: "admin")
    end

    # Supprimer les colonnes non utilisées pour magic links
    execute("ALTER TABLE users DROP COLUMN IF EXISTS hashed_password", "")
    execute("ALTER TABLE users DROP COLUMN IF EXISTS confirmed_at", "")

    # Ajouter la contrainte de rôle si elle n'existe pas
    execute(
      """
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'valid_role') THEN
          ALTER TABLE users ADD CONSTRAINT valid_role CHECK (role IN ('admin'));
        END IF;
      END$$;
      """,
      ""
    )

    # Renommer users_tokens en magic_links si nécessaire
    execute(
      """
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users_tokens') THEN
          ALTER TABLE users_tokens RENAME TO magic_links;
        END IF;
      END$$;
      """,
      ""
    )

    # Modifier la structure de magic_links
    execute(
      """
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'magic_links') THEN
          -- Modifier le type de token si nécessaire
          ALTER TABLE magic_links DROP COLUMN IF EXISTS context;
          ALTER TABLE magic_links DROP COLUMN IF EXISTS sent_to;
          ALTER TABLE magic_links DROP COLUMN IF EXISTS authenticated_at;

          -- Ajouter les nouvelles colonnes
          ALTER TABLE magic_links ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes');
          ALTER TABLE magic_links ADD COLUMN IF NOT EXISTS used_at TIMESTAMPTZ;

          -- Modifier la colonne token
          ALTER TABLE magic_links ALTER COLUMN token TYPE VARCHAR(255);
        END IF;
      END$$;
      """,
      ""
    )

    # Supprimer les anciens index
    execute("DROP INDEX IF EXISTS users_tokens_user_id_index", "")
    execute("DROP INDEX IF EXISTS users_tokens_context_token_index", "")

    # Créer les nouveaux index
    create_if_not_exists(index(:magic_links, [:expires_at]))
  end
end
