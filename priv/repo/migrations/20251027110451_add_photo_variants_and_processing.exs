defmodule Portfolio.Repo.Migrations.AddPhotoVariantsAndProcessing do
  use Ecto.Migration

  def change do
    alter table(:photos) do
      add :variants, :map, default: %{}
      add :processing_status, :string, default: "pending", null: false
    end

    create index(:photos, [:processing_status])

    # Constraint to validate enum values
    create constraint(:photos, :processing_status_must_be_valid,
             check: "processing_status IN ('pending', 'processing', 'completed', 'failed')"
           )
  end
end
