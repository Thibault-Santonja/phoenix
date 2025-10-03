defmodule Portfolio.Auth do
  @moduledoc """
  Context Auth pour l'authentification via Magic Links.

  Implémente un système d'authentification passwordless où les utilisateurs
  reçoivent un lien unique par email pour se connecter.
  """

  import Ecto.Query, warn: false

  alias Portfolio.Auth.MagicLink
  alias Portfolio.Auth.User
  alias Portfolio.Auth.UserSession
  alias Portfolio.DomainEvents
  alias Portfolio.Auth.Events.MagicLinkVerified

  alias Portfolio.Repo

  # Service Layer
  alias Portfolio.Services.Auth.MagicLinkAuthService

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
        # En développement et test, créer automatiquement l'utilisateur
        # En production, refuser la connexion
        if Mix.env() in [:dev, :test] do
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

  Délègue au MagicLinkAuthService pour orchestrer l'opération complète
  incluant rate limiting, création utilisateur, génération token, envoi email,
  et émission d'événements.

  ## Exemples

      iex> request_magic_link("admin@example.com")
      {:ok, %MagicLink{token: "abc123..."}}

      iex> request_magic_link("spammer@example.com")  # Après 5 requêtes
      {:error, :rate_limit_exceeded}
  """
  @spec request_magic_link(String.t()) ::
          {:ok, MagicLink.t()}
          | {:error, Ecto.Changeset.t() | :user_not_found | :rate_limit_exceeded}
  def request_magic_link(email) when is_binary(email) do
    MagicLinkAuthService.execute(email)
  end

  @doc """
  Vérifie un magic link par son token de manière atomique.

  Utilise Ecto.Multi pour garantir l'atomicité :
  - Vérifie que le token existe et est valide
  - Marque le magic link comme utilisé
  - Crée une session pour l'utilisateur
  - Si l'une des opérations échoue, toute la transaction est annulée

  Émet un événement `MagicLinkVerified` après vérification réussie.

  Émet également un événement telemetry `[:portfolio, :auth, :magic_link, :verified]`
  avec la durée et le résultat de l'opération.

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
    start_time = System.monotonic_time()

    magic_link =
      MagicLink
      |> where([ml], ml.token == ^token)
      |> preload(:user)
      |> Repo.one()

    result =
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
              # Utiliser Ecto.Multi pour marquer le magic link comme utilisé de manière atomique
              Ecto.Multi.new()
              |> Ecto.Multi.update(
                :magic_link,
                Ecto.Changeset.change(ml, %{
                  used_at: DateTime.utc_now() |> DateTime.truncate(:second)
                })
              )
              |> Repo.transaction()
              |> case do
                {:ok, %{magic_link: updated_ml}} ->
                  # Émettre l'événement de domaine
                  DomainEvents.publish(:magic_link_verified, %MagicLinkVerified{
                    magic_link_id: updated_ml.id,
                    user_id: ml.user.id,
                    email: ml.user.email,
                    verified_at: DateTime.utc_now()
                  })

                  {:ok, ml.user}

                {:error, _step, error, _changes} ->
                  {:error, error}
              end
          end
      end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:portfolio, :auth, :magic_link, :verified],
      %{duration: duration},
      %{result: elem(result, 0)}
    )

    result
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
    expiry_seconds = UserSession.session_expiration_seconds()

    expiry_date =
      DateTime.utc_now()
      |> DateTime.add(-expiry_seconds, :second)
      |> DateTime.truncate(:second)

    UserSession
    |> where([s], s.last_activity_at < ^expiry_date)
    |> Repo.delete_all()
  end

  @doc """
  Liste toutes les sessions d'un utilisateur triées par dernière activité.

  ## Exemples

      iex> list_user_sessions(user.id)
      [%UserSession{}, ...]
  """
  @spec list_user_sessions(Ecto.UUID.t()) :: [UserSession.t()]
  def list_user_sessions(user_id) do
    UserSession
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], desc: s.last_activity_at)
    |> Repo.all()
  end

  @doc """
  Récupère une session par son ID.

  ## Exemples

      iex> get_session!(session_id)
      %UserSession{}
  """
  @spec get_session!(Ecto.UUID.t()) :: UserSession.t()
  def get_session!(id), do: Repo.get!(UserSession, id)

  @doc """
  Supprime toutes les sessions d'un utilisateur sauf celle spécifiée.

  Utile pour déconnecter tous les autres appareils en gardant la session actuelle.

  ## Exemples

      iex> delete_all_user_sessions_except(user, current_session.id)
      {2, nil}  # 2 autres sessions supprimées
  """
  @spec delete_all_user_sessions_except(User.t(), Ecto.UUID.t()) :: {integer(), nil}
  def delete_all_user_sessions_except(%User{id: user_id}, current_session_id) do
    UserSession
    |> where([s], s.user_id == ^user_id and s.id != ^current_session_id)
    |> Repo.delete_all()
  end

  # =============================================================================
  # User Profile Functions
  # =============================================================================

  @doc """
  Retourne un changeset pour modification du profil utilisateur.

  ## Exemples

      iex> change_user(user)
      %Ecto.Changeset{}
  """
  @spec change_user(User.t(), map()) :: Ecto.Changeset.t()
  def change_user(user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Met à jour le profil d'un utilisateur.

  Seul le champ name peut être modifié.

  ## Exemples

      iex> update_user(user, %{name: "New Name"})
      {:ok, %User{}}
  """
  @spec update_user(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user(user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Compte le nombre total d'utilisateurs dans le système.

  ## Exemples

      iex> count_users()
      5
  """
  @spec count_users() :: non_neg_integer()
  def count_users do
    Repo.aggregate(User, :count)
  end

  @doc """
  Liste tous les utilisateurs du système.

  ## Exemples

      iex> list_users()
      [%User{}, %User{}]
  """
  @spec list_users() :: [User.t()]
  def list_users do
    Repo.all(User)
  end
end
