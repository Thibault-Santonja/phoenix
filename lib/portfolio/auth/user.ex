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

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          email: String.t(),
          name: String.t() | nil,
          role: String.t(),
          magic_links: [MagicLink.t()] | Ecto.Association.NotLoaded.t(),
          user_sessions: [UserSession.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, :string, default: "admin"

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
    |> validate_inclusion(:role, ["admin", "superadmin"])
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
    |> put_change(:role, "admin")
    |> unique_constraint(:email)
  end

  # Validation de l'email
  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "doit être une adresse email valide")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Portfolio.Repo)
    |> unique_constraint(:email)
  end
end
