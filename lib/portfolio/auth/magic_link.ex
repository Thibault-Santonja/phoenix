defmodule Portfolio.Auth.MagicLink do
  @moduledoc """
  Schema MagicLink pour l'authentification passwordless.

  Un magic link est un lien unique à usage unique qui expire après 15 minutes.
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
          expires_at: DateTime.t(),
          used_at: DateTime.t() | nil,
          inserted_at: NaiveDateTime.t() | nil
        }

  schema "magic_links" do
    belongs_to :user, User

    field :token, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Changeset pour la création d'un magic link.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(magic_link, attrs) do
    magic_link
    |> cast(attrs, [:user_id, :token, :expires_at])
    |> validate_required([:user_id, :token, :expires_at])
    |> unique_constraint(:token)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Vérifie si le magic link a expiré.

  ## Exemples

      iex> expired?(%MagicLink{expires_at: ~U[2024-01-01 10:00:00Z]})
      true

      iex> expired?(%MagicLink{expires_at: DateTime.add(DateTime.utc_now(), 10, :minute)})
      false
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Vérifie si le magic link a déjà été utilisé.

  ## Exemples

      iex> used?(%MagicLink{used_at: ~U[2024-01-01 10:00:00Z]})
      true

      iex> used?(%MagicLink{used_at: nil})
      false
  """
  @spec used?(t()) :: boolean()
  def used?(%__MODULE__{used_at: nil}), do: false
  def used?(%__MODULE__{used_at: _}), do: true

  @doc """
  Vérifie si le magic link est valide (non expiré et non utilisé).

  ## Exemples

      iex> valid?(%MagicLink{expires_at: future_time, used_at: nil})
      true

      iex> valid?(%MagicLink{expires_at: past_time, used_at: nil})
      false

      iex> valid?(%MagicLink{expires_at: future_time, used_at: ~U[2024-01-01 10:00:00Z]})
      false
  """
  @spec valid?(t()) :: boolean()
  def valid?(magic_link) do
    !expired?(magic_link) && !used?(magic_link)
  end
end
