defmodule Portfolio.Auth.User do
  @moduledoc """
  Schema User pour l'authentification admin.

  Les utilisateurs s'authentifient via magic links (passwordless).
  Seuls les admins peuvent accéder à l'interface d'administration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolio.Auth.{DisposableEmailChecker, EmailType, MagicLink, MXValidator, UserSession}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          email: String.t() | nil,
          name: String.t() | nil,
          role: atom(),
          magic_links: [MagicLink.t()] | Ecto.Association.NotLoaded.t(),
          user_sessions: [UserSession.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "users" do
    field :email, EmailType
    field :name, :string
    field :role, Ecto.Enum, values: [:admin, :user], default: :user

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
    |> validate_inclusion(:role, [:admin, :user])
    |> unique_constraint(:email)
  end

  @doc """
  Changeset pour l'enregistrement d'un nouvel utilisateur.

  Par défaut, les nouveaux utilisateurs ont le rôle :user.
  Le rôle :admin doit être attribué manuellement par un administrateur existant.
  """
  @spec registration_changeset(t(), map()) :: Ecto.Changeset.t()
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> validate_required([:email])
    |> validate_email()
    |> put_change(:role, :user)
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

  Protection: Un admin ne peut pas modifier son propre rôle (sécurité).
  Pour modifier le rôle, passez l'ID de l'admin courant via :current_user_id.
  """
  @spec admin_changeset(t(), map(), keyword()) :: Ecto.Changeset.t()
  def admin_changeset(user, attrs, opts \\ []) do
    current_user_id = Keyword.get(opts, :current_user_id)

    user
    |> cast(attrs, [:role, :name])
    |> validate_required([:role])
    |> validate_inclusion(:role, [:admin, :user])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_not_self_role_modification(current_user_id)
  end

  # Valide qu'un utilisateur ne modifie pas son propre rôle
  defp validate_not_self_role_modification(changeset, nil), do: changeset

  defp validate_not_self_role_modification(changeset, current_user_id) do
    user_id = get_field(changeset, :id)
    role_changed? = get_change(changeset, :role) != nil

    if user_id == current_user_id and role_changed? do
      add_error(changeset, :role, "vous ne pouvez pas modifier votre propre rôle")
    else
      changeset
    end
  end

  @doc """
  Changeset pour le bootstrap de l'admin initial.

  **ATTENTION:** Ce changeset est uniquement destiné à être utilisé pour créer
  le tout premier administrateur du système (bootstrap). Il permet de créer
  directement un utilisateur avec le rôle :admin sans validation préalable.

  Ne doit être utilisé que dans :
  - Seeds (priv/repo/seeds.exs)
  - Release tasks de bootstrap
  - Scripts d'initialisation en production

  Pour toute autre création d'utilisateur, utilisez `registration_changeset/2`.
  """
  @spec bootstrap_admin_changeset(t(), map()) :: Ecto.Changeset.t()
  def bootstrap_admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :role])
    |> validate_required([:email, :role])
    |> validate_email()
    |> validate_inclusion(:role, [:admin, :user])
    |> unique_constraint(:email)
  end

  # Validation de l'email
  # Note: EmailType gère déjà la validation du format et la normalisation (lowercase, trim)
  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_length(:email, max: 320)
    |> validate_not_disposable_email()
    |> validate_mx_records()
    |> unsafe_validate_unique(:email, Portfolio.Repo)
    |> unique_constraint(:email)
  end

  # Valide que l'email n'utilise pas un domaine jetable
  defp validate_not_disposable_email(changeset) do
    email = get_field(changeset, :email)

    if email && DisposableEmailChecker.disposable?(email) do
      add_error(
        changeset,
        :email,
        "les adresses email temporaires ne sont pas autorisées"
      )
    else
      changeset
    end
  end

  # Valide que le domaine de l'email possède des enregistrements MX valides
  defp validate_mx_records(changeset) do
    email = get_field(changeset, :email)

    if email && !MXValidator.valid_mx?(email) do
      add_error(
        changeset,
        :email,
        "ce domaine ne peut pas recevoir d'emails"
      )
    else
      changeset
    end
  end
end
