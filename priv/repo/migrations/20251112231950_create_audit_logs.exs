defmodule Portfolio.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :binary_id
      add :changes, :map, default: %{}
      add :metadata, :map, default: %{}
      add :performed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :ip_address, :string
      add :user_agent, :string

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:audit_logs, [:action])
    create index(:audit_logs, [:resource_type])
    create index(:audit_logs, [:resource_id])
    create index(:audit_logs, [:performed_by_id])
    create index(:audit_logs, [:inserted_at])
    create index(:audit_logs, [:resource_type, :resource_id])
  end
end
