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
  Vérifie si la session a expiré selon la configuration.

  La durée d'expiration est configurable via :portfolio, :auth, :session_expiration_seconds
  Par défaut: 1 heure (3600 secondes)
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{last_activity_at: last_activity_at}) do
    expiry_seconds = session_expiration_seconds()
    expiry_date = DateTime.add(last_activity_at, expiry_seconds, :second)
    DateTime.compare(DateTime.utc_now(), expiry_date) == :gt
  end

  @doc """
  Retourne la durée d'expiration en secondes depuis la configuration.

  Peut être surchargée via la variable d'environnement SESSION_EXPIRATION_SECONDS
  """
  @spec session_expiration_seconds() :: integer()
  def session_expiration_seconds do
    Application.get_env(:portfolio, :auth, [])
    # 1h par défaut
    |> Keyword.get(:session_expiration_seconds, 3600)
  end
end
