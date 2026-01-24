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

  Le token est automatiquement hashé avant d'être stocké en DB pour la sécurité.
  """
  def changeset(user_session, attrs) do
    user_session
    |> cast(attrs, [:user_id, :token, :last_activity_at])
    |> validate_required([:user_id, :token, :last_activity_at])
    |> hash_token()
    |> unique_constraint(:token)
  end

  @doc """
  Hashe un token pour le stocker en DB de manière sécurisée.

  Utilise SHA-256 pour créer un hash irréversible du token.
  Cela protège contre le vol de tokens si la DB est compromise.

  ## Exemples

      iex> UserSession.hash_token_value("raw_token_here")
      "8a4f54d1a143b3031b523b1f5b37254d1d99e3479d5d70a16090d360ad993dac"
  """
  @spec hash_token_value(String.t()) :: String.t()
  def hash_token_value(token) do
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end

  # Hashe le champ :token dans un changeset
  defp hash_token(%Ecto.Changeset{valid?: true, changes: %{token: token}} = changeset) do
    put_change(changeset, :token, hash_token_value(token))
  end

  defp hash_token(changeset), do: changeset

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
