defmodule Portfolio.Auth.User do
  @moduledoc """
  Schema User pour l'authentification admin.

  Les utilisateurs s'authentifient via magic links (passwordless).
  Seuls les admins peuvent accéder à l'interface d'administration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolio.Auth.{MagicLink, UserSession}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # RFC 5322 compliant email regex
  # Allows most valid email formats while being strict enough to catch common errors
  @email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          email: String.t(),
          name: String.t() | nil,
          role: atom(),
          magic_links: [MagicLink.t()] | Ecto.Association.NotLoaded.t(),
          user_sessions: [UserSession.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, Ecto.Enum, values: [:admin, :superadmin, :user], default: :admin

    has_many :magic_links, MagicLink
    has_many :user_sessions, UserSession

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset pour la création/modification d'un utilisateur.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :role])
    |> validate_required([:email, :role])
    |> validate_email()
    |> validate_inclusion(:role, [:admin, :superadmin, :user])
    |> unique_constraint(:email)
  end

  @doc """
  Changeset pour l'enregistrement d'un nouvel utilisateur.
  """
  @spec registration_changeset(t(), map()) :: Ecto.Changeset.t()
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> validate_required([:email])
    |> validate_email()
    |> put_change(:role, :admin)
    |> unique_constraint(:email)
  end

  @doc """
  Changeset pour la modification du profil utilisateur.

  Seul le champ name est modifiable. Les champs email et role
  ne peuvent pas être modifiés via le profil.
  """
  @spec profile_changeset(t(), map()) :: Ecto.Changeset.t()
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name])
    |> validate_length(:name, min: 2, max: 100)
  end

  @doc """
  Changeset pour la modification d'un utilisateur par un admin.

  Permet de modifier le rôle d'un utilisateur.
  L'email ne peut pas être modifié pour des raisons de sécurité.
  """
  @spec admin_changeset(t(), map()) :: Ecto.Changeset.t()
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:role, :name])
    |> validate_required([:role])
    |> validate_inclusion(:role, [:admin, :superadmin, :user])
    |> validate_length(:name, min: 2, max: 100)
  end

  # Validation de l'email avec RFC 5322
  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, @email_regex, message: "doit être une adresse email valide")
    |> validate_length(:email, max: 160)
    |> update_change(:email, &String.downcase/1)
    |> unsafe_validate_unique(:email, Portfolio.Repo)
    |> unique_constraint(:email)
  end
end
