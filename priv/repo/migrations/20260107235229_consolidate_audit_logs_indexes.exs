defmodule Portfolio.Repo.Migrations.ConsolidateAuditLogsIndexes do
  @moduledoc """
  Consolide les indexes de la table audit_logs pour améliorer les performances.

  ## Contexte

  La table audit_logs avait 6 indexes individuels dont plusieurs sont redondants.
  Cette migration consolide ces indexes en indexes composites optimisés pour
  les requêtes réelles du repository.

  ## Requêtes du Repository

  1. **get_by_resource/3:**
     ```sql
     SELECT * FROM audit_logs
     WHERE resource_type = $1 AND resource_id = $2
     ORDER BY inserted_at DESC
     LIMIT $3
     ```

  2. **get_by_performer/2:**
     ```sql
     SELECT * FROM audit_logs
     WHERE performed_by_id = $1
     ORDER BY inserted_at DESC
     LIMIT $2
     ```

  ## Indexes Supprimés (redondants)

  - `audit_logs_action_index` - rarement filtré seul
  - `audit_logs_resource_type_index` - couvert par index composite
  - `audit_logs_resource_id_index` - couvert par index composite
  - `audit_logs_inserted_at_index` - couvert par index composite

  ## Indexes Conservés/Ajoutés

  - `audit_logs_resource_inserted_at_index` - (resource_type, resource_id, inserted_at)
  - `audit_logs_performed_by_id_index` - sera modifié en composite avec inserted_at

  ## Impact

  - Réduction de l'espace disque (4 indexes en moins)
  - Amélioration des performances d'écriture (moins d'indexes à maintenir)
  - Performances de lecture maintenues via indexes composites optimisés
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # 1. Créer un index composite pour get_by_performer avec tri
    # Optimise: WHERE performed_by_id = $1 ORDER BY inserted_at DESC
    create index(:audit_logs, [:performed_by_id, :inserted_at],
             name: :audit_logs_performer_inserted_at_index,
             concurrently: true
           )

    # 2. Supprimer les indexes redondants
    # L'index action est rarement utilisé seul
    drop_if_exists index(:audit_logs, [:action],
                     name: :audit_logs_action_index,
                     concurrently: true
                   )

    # resource_type seul est couvert par l'index composite
    drop_if_exists index(:audit_logs, [:resource_type],
                     name: :audit_logs_resource_type_index,
                     concurrently: true
                   )

    # resource_id seul est couvert par l'index composite
    drop_if_exists index(:audit_logs, [:resource_id],
                     name: :audit_logs_resource_id_index,
                     concurrently: true
                   )

    # inserted_at seul est couvert par les index composites
    drop_if_exists index(:audit_logs, [:inserted_at],
                     name: :audit_logs_inserted_at_index,
                     concurrently: true
                   )

    # Supprimer l'ancien index performed_by_id simple (remplacé par composite)
    drop_if_exists index(:audit_logs, [:performed_by_id],
                     name: :audit_logs_performed_by_id_index,
                     concurrently: true
                   )
  end

  def down do
    # Restaurer les indexes simples
    create_if_not_exists index(:audit_logs, [:action],
                           name: :audit_logs_action_index,
                           concurrently: true
                         )

    create_if_not_exists index(:audit_logs, [:resource_type],
                           name: :audit_logs_resource_type_index,
                           concurrently: true
                         )

    create_if_not_exists index(:audit_logs, [:resource_id],
                           name: :audit_logs_resource_id_index,
                           concurrently: true
                         )

    create_if_not_exists index(:audit_logs, [:inserted_at],
                           name: :audit_logs_inserted_at_index,
                           concurrently: true
                         )

    create_if_not_exists index(:audit_logs, [:performed_by_id],
                           name: :audit_logs_performed_by_id_index,
                           concurrently: true
                         )

    # Supprimer l'index composite créé
    drop_if_exists index(:audit_logs, [:performed_by_id, :inserted_at],
                     name: :audit_logs_performer_inserted_at_index,
                     concurrently: true
                   )
  end
end
