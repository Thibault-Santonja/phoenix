defmodule Portfolio.Auth.UserSession do
  @moduledoc """
  Schéma pour les sessions utilisateur avec tokens.

  Permet de:
  - Révoquer des sessions spécifiques
  - Expirer les sessions après inactivité
  - Tracer les sessions actives
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolio.Auth.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Session expire après 30 jours d'inactivité
  @session_validity_days 30

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t(),
          user: User.t() | Ecto.Association.NotLoaded.t(),
          token: String.t(),
          last_activity_at: DateTime.t(),
          inserted_at: DateTime.t() | nil
        }

  schema "user_sessions" do
    belongs_to :user, User
    field :token, :string
    field :last_activity_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Changeset pour créer une nouvelle session.
  """
  def changeset(user_session, attrs) do
    user_session
    |> cast(attrs, [:user_id, :token, :last_activity_at])
    |> validate_required([:user_id, :token, :last_activity_at])
    |> unique_constraint(:token)
  end

  @doc """
  Vérifie si la session a expiré (30 jours d'inactivité).
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{last_activity_at: last_activity_at}) do
    expiry_date = DateTime.add(last_activity_at, @session_validity_days, :day)
    DateTime.compare(DateTime.utc_now(), expiry_date) == :gt
  end

  @doc """
  Retourne le nombre de jours de validité d'une session.
  """
  @spec validity_days() :: integer()
  def validity_days, do: @session_validity_days
end
