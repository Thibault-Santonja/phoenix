defmodule Portfolio.Auth do
  @moduledoc """
  Context Auth pour l'authentification via Magic Links.

  Implémente un système d'authentification passwordless où les utilisateurs
  reçoivent un lien unique par email pour se connecter.
  """

  import Ecto.Query, warn: false

  alias Portfolio.Repo
  alias Portfolio.Auth.{User, MagicLink, UserSession, Mailer}

  # =============================================================================
  # User Functions
  # =============================================================================

  @doc """
  Récupère un utilisateur par son email.

  ## Exemples

      iex> get_user_by_email("admin@example.com")
      {:ok, %User{}}

      iex> get_user_by_email("unknown@example.com")
      {:error, :not_found}
  """
  @spec get_user_by_email(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def get_user_by_email(email) when is_binary(email) do
    case Repo.get_by(User, email: email) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc """
  Récupère ou crée un utilisateur par email.

  En développement, l'utilisateur est créé automatiquement s'il n'existe pas.
  En production, seuls les utilisateurs existants peuvent se connecter.

  ## Exemples

      iex> get_or_create_user("admin@example.com")
      {:ok, %User{}}

      iex> get_or_create_user("unknown@example.com")  # En production
      {:error, :user_not_found}
  """
  @spec get_or_create_user(String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | :user_not_found}
  def get_or_create_user(email) when is_binary(email) do
    case get_user_by_email(email) do
      {:ok, user} ->
        {:ok, user}

      {:error, :not_found} ->
        # En développement, créer automatiquement l'utilisateur
        # En production, refuser la connexion
        if Mix.env() == :dev do
          %User{}
          |> User.registration_changeset(%{email: email})
          |> Repo.insert()
        else
          {:error, :user_not_found}
        end
    end
  end

  @doc """
  Récupère un utilisateur par son ID.
  """
  @spec get_user(Ecto.UUID.t()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  # =============================================================================
  # Magic Link Functions
  # =============================================================================

  @doc """
  Demande un magic link pour un email donné.

  Crée un utilisateur s'il n'existe pas, génère un token unique,
  et crée un magic link valide 15 minutes.

  ## Exemples

      iex> request_magic_link("admin@example.com")
      {:ok, %MagicLink{token: "abc123..."}}
  """
  @spec request_magic_link(String.t()) :: {:ok, MagicLink.t()} | {:error, Ecto.Changeset.t()}
  def request_magic_link(email) when is_binary(email) do
    with {:ok, user} <- get_or_create_user(email),
         {:ok, magic_link} <- create_magic_link(user) do
      # Envoyer l'email avec le magic link
      Mailer.send_magic_link_email(user, magic_link)

      {:ok, magic_link}
    end
  end

  @doc """
  Vérifie un magic link par son token.

  Retourne l'utilisateur si le token est valide (non expiré, non utilisé).
  Marque le magic link comme utilisé si valide.

  ## Exemples

      iex> verify_magic_link("valid_token")
      {:ok, %User{}}

      iex> verify_magic_link("invalid_token")
      {:error, :invalid_token}

      iex> verify_magic_link("expired_token")
      {:error, :expired}
  """
  @spec verify_magic_link(String.t()) ::
          {:ok, User.t()} | {:error, :invalid_token | :expired | :already_used}
  def verify_magic_link(token) when is_binary(token) do
    magic_link =
      MagicLink
      |> where([ml], ml.token == ^token)
      |> preload(:user)
      |> Repo.one()

    case magic_link do
      nil ->
        {:error, :invalid_token}

      %MagicLink{} = ml ->
        cond do
          MagicLink.used?(ml) ->
            {:error, :already_used}

          MagicLink.expired?(ml) ->
            {:error, :expired}

          true ->
            # Marquer comme utilisé
            ml
            |> Ecto.Changeset.change(%{used_at: DateTime.utc_now() |> DateTime.truncate(:second)})
            |> Repo.update()

            {:ok, ml.user}
        end
    end
  end

  @doc """
  Supprime tous les magic links expirés.

  Utile pour un job de nettoyage périodique.

  ## Exemples

      iex> delete_expired_magic_links()
      {5, nil}  # 5 magic links supprimés
  """
  @spec delete_expired_magic_links() :: {integer(), nil}
  def delete_expired_magic_links do
    now = DateTime.utc_now()

    MagicLink
    |> where([ml], ml.expires_at < ^now)
    |> Repo.delete_all()
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  # Crée un magic link pour un utilisateur
  @spec create_magic_link(User.t()) :: {:ok, MagicLink.t()} | {:error, Ecto.Changeset.t()}
  defp create_magic_link(user) do
    token = generate_token()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(15, :minute)
      |> DateTime.truncate(:second)

    %MagicLink{}
    |> MagicLink.changeset(%{
      user_id: user.id,
      token: token,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  # Génère un token sécurisé de 32 bytes
  @spec generate_token() :: String.t()
  defp generate_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  # =============================================================================
  # Session Functions
  # =============================================================================

  @doc """
  Crée une nouvelle session pour un utilisateur après connexion réussie.

  ## Exemples

      iex> create_session(user)
      {:ok, %UserSession{token: "abc123..."}}
  """
  @spec create_session(User.t()) :: {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  def create_session(%User{} = user) do
    token = generate_token()

    %UserSession{}
    |> UserSession.changeset(%{
      user_id: user.id,
      token: token,
      last_activity_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
  end

  @doc """
  Récupère une session par son token.

  Retourne nil si le token n'existe pas ou si la session a expiré.

  ## Exemples

      iex> get_session_by_token("valid_token")
      %UserSession{user: %User{}}

      iex> get_session_by_token("invalid_token")
      nil
  """
  @spec get_session_by_token(String.t()) :: UserSession.t() | nil
  def get_session_by_token(token) when is_binary(token) do
    UserSession
    |> where([s], s.token == ^token)
    |> preload(:user)
    |> Repo.one()
    |> case do
      nil ->
        nil

      session ->
        if UserSession.expired?(session) do
          delete_session(session)
          nil
        else
          session
        end
    end
  end

  @doc """
  Met à jour l'activité d'une session (pour prolonger sa durée de vie).

  ## Exemples

      iex> update_session_activity(session)
      {:ok, %UserSession{}}
  """
  @spec update_session_activity(UserSession.t()) ::
          {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  def update_session_activity(%UserSession{} = session) do
    session
    |> Ecto.Changeset.change(%{
      last_activity_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Supprime une session (logout).

  ## Exemples

      iex> delete_session(session)
      {:ok, %UserSession{}}
  """
  @spec delete_session(UserSession.t()) :: {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  def delete_session(%UserSession{} = session) do
    Repo.delete(session)
  end

  @doc """
  Supprime toutes les sessions d'un utilisateur (logout de tous les appareils).

  ## Exemples

      iex> delete_all_user_sessions(user)
      {3, nil}  # 3 sessions supprimées
  """
  @spec delete_all_user_sessions(User.t()) :: {integer(), nil}
  def delete_all_user_sessions(%User{id: user_id}) do
    UserSession
    |> where([s], s.user_id == ^user_id)
    |> Repo.delete_all()
  end

  @doc """
  Supprime toutes les sessions expirées (job de nettoyage).

  ## Exemples

      iex> delete_expired_sessions()
      {10, nil}  # 10 sessions expirées supprimées
  """
  @spec delete_expired_sessions() :: {integer(), nil}
  def delete_expired_sessions do
    expiry_date =
      DateTime.utc_now()
      |> DateTime.add(-UserSession.validity_days(), :day)
      |> DateTime.truncate(:second)

    UserSession
    |> where([s], s.last_activity_at < ^expiry_date)
    |> Repo.delete_all()
  end
end
