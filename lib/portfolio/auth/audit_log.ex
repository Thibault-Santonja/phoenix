defmodule Portfolio.Auth.AuditLog do
  @moduledoc """
  Schema pour les logs d'audit des modifications sensibles.

  Enregistre les actions administratives et les modifications de sécurité
  pour la traçabilité et la conformité.

  ## Actions auditées

  - `:user_role_changed` - Changement de rôle utilisateur
  - `:user_deleted` - Suppression d'utilisateur
  - `:sessions_revoked` - Révocation de sessions
  - `:magic_link_sent` - Envoi de magic link par admin

  ## Champs

  - `action` - Type d'action effectuée (atom converti en string)
  - `resource_type` - Type de ressource modifiée (ex: "User", "Session")
  - `resource_id` - ID de la ressource modifiée
  - `changes` - Map des changements (before/after)
  - `metadata` - Métadonnées additionnelles (contexte, raison, etc.)
  - `performed_by_id` - ID de l'utilisateur ayant effectué l'action
  - `ip_address` - Adresse IP de l'utilisateur
  - `user_agent` - User agent du navigateur
  - `inserted_at` - Date et heure de l'action

  ## Exemples

      # Log d'un changement de rôle
      %AuditLog{
        action: "user_role_changed",
        resource_type: "User",
        resource_id: "123e4567-e89b-12d3-a456-426614174000",
        changes: %{
          "role" => %{"from" => "user", "to" => "admin"}
        },
        performed_by_id: "admin-user-id",
        ip_address: "192.168.1.1",
        metadata: %{"reason" => "promotion"}
      }

      # Log d'une suppression
      %AuditLog{
        action: "user_deleted",
        resource_type: "User",
        resource_id: "user-id",
        changes: %{
          "email" => "deleted@example.com",
          "role" => "user"
        },
        performed_by_id: "admin-user-id"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolio.Auth.User

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          action: String.t() | nil,
          resource_type: String.t() | nil,
          resource_id: Ecto.UUID.t() | nil,
          changes: map(),
          metadata: map(),
          performed_by_id: Ecto.UUID.t() | nil,
          performed_by: User.t() | Ecto.Association.NotLoaded.t(),
          ip_address: String.t() | nil,
          user_agent: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :changes, :map, default: %{}
    field :metadata, :map, default: %{}
    field :ip_address, :string
    field :user_agent, :string

    belongs_to :performed_by, User, foreign_key: :performed_by_id

    field :inserted_at, :utc_datetime_usec
  end

  @doc """
  Crée un changeset pour un log d'audit.

  ## Paramètres requis

  - `:action` - Type d'action (string)
  - `:resource_type` - Type de ressource (string)

  ## Paramètres optionnels

  - `:resource_id` - ID de la ressource (UUID)
  - `:changes` - Map des changements
  - `:metadata` - Métadonnées additionnelles
  - `:performed_by_id` - ID de l'utilisateur
  - `:ip_address` - Adresse IP
  - `:user_agent` - User agent

  ## Exemples

      iex> changeset(%AuditLog{}, %{
      ...>   action: "user_role_changed",
      ...>   resource_type: "User",
      ...>   resource_id: "123e4567-e89b-12d3-a456-426614174000",
      ...>   changes: %{"role" => %{"from" => "user", "to" => "admin"}},
      ...>   performed_by_id: "admin-id"
      ...> })
      %Ecto.Changeset{valid?: true}
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [
      :action,
      :resource_type,
      :resource_id,
      :changes,
      :metadata,
      :performed_by_id,
      :ip_address,
      :user_agent
    ])
    |> validate_required([:action, :resource_type])
    |> validate_length(:action, min: 1, max: 255)
    |> validate_length(:resource_type, min: 1, max: 255)
    |> validate_length(:ip_address, max: 45)
    |> validate_length(:user_agent, max: 1000)
    |> put_timestamp()
  end

  # Ajoute le timestamp actuel si non présent
  defp put_timestamp(changeset) do
    if get_field(changeset, :inserted_at) do
      changeset
    else
      put_change(changeset, :inserted_at, DateTime.utc_now())
    end
  end
end
