defmodule Portfolio.Auth do
  @moduledoc """
  Facade publique du contexte Auth pour l'authentification via Magic Links.

  Implémente un système d'authentification passwordless où les utilisateurs
  reçoivent un lien unique par email pour se connecter.

  ## Architecture

  Ce module sert de facade (pattern Facade) et délègue aux services spécialisés :

  - **UserService** : Gestion du cycle de vie des utilisateurs
  - **MagicLinkService** : Gestion des magic links passwordless
  - **SessionService** : Gestion des sessions utilisateur

  Cette séparation permet de :
  - Respecter le principe de responsabilité unique (SRP)
  - Faciliter les tests unitaires de chaque service
  - Améliorer la maintenabilité (modules < 300 lignes)
  - Garder une API publique stable et simple

  ## Exemples

      # Authentification complète
      iex> Auth.request_magic_link("user@example.com")
      {:ok, %MagicLink{}}

      iex> Auth.verify_magic_link(token)
      {:ok, %User{}}

      iex> Auth.create_session(user)
      {:ok, %UserSession{}}

      # Gestion des utilisateurs
      iex> Auth.get_user_by_email("user@example.com")
      {:ok, %User{}}

      iex> Auth.list_users()
      [%User{}, ...]
  """

  alias Portfolio.Auth.{MagicLink, User, UserSession}
  alias Portfolio.Auth.{MagicLinkService, SessionService, UserService}

  # =============================================================================
  # User API - Délégation à UserService
  # =============================================================================

  @doc """
  Récupère un utilisateur par son email.

  Délégué à `Portfolio.Auth.UserService.get_user_by_email/1`.
  """
  @spec get_user_by_email(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  defdelegate get_user_by_email(email), to: UserService

  @doc """
  Récupère ou crée un utilisateur par email.

  Délégué à `Portfolio.Auth.UserService.get_or_create_user/1`.
  """
  @spec get_or_create_user(String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | :user_not_found}
  defdelegate get_or_create_user(email), to: UserService

  @doc """
  Récupère un utilisateur par son ID.

  Délégué à `Portfolio.Auth.UserService.get_user/1`.
  """
  @spec get_user(Ecto.UUID.t()) :: {:ok, User.t()} | {:error, :not_found}
  defdelegate get_user(id), to: UserService

  @doc """
  Liste tous les utilisateurs avec filtres optionnels.

  Délégué à `Portfolio.Auth.UserService.list_users/1`.
  """
  @spec list_users(keyword()) :: [User.t()]
  defdelegate list_users(opts \\ []), to: UserService

  @doc """
  Retourne un changeset pour modification du profil utilisateur.

  Délégué à `Portfolio.Auth.UserService.change_user/2`.
  """
  @spec change_user(User.t(), map()) :: Ecto.Changeset.t()
  defdelegate change_user(user, attrs \\ %{}), to: UserService

  @doc """
  Met à jour le profil d'un utilisateur.

  Délégué à `Portfolio.Auth.UserService.update_user/2`.
  """
  @spec update_user(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_user(user, attrs), to: UserService

  @doc """
  Met à jour un utilisateur via l'interface admin.

  Délégué à `Portfolio.Auth.UserService.update_user_as_admin/3`.
  """
  @spec update_user_as_admin(User.t(), map(), keyword()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_user_as_admin(user, attrs, opts \\ []), to: UserService

  @doc """
  Supprime un utilisateur et toutes ses données associées.

  Délégué à `Portfolio.Auth.UserService.delete_user/1`.
  """
  @spec delete_user(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_user(user), to: UserService

  @doc """
  Compte le nombre total d'utilisateurs.

  Délégué à `Portfolio.Auth.UserService.count_users/0`.
  """
  @spec count_users() :: non_neg_integer()
  defdelegate count_users(), to: UserService

  @doc """
  Compte le nombre d'administrateurs.

  Délégué à `Portfolio.Auth.UserService.count_admin_users/0`.
  """
  @spec count_admin_users() :: non_neg_integer()
  defdelegate count_admin_users(), to: UserService

  @doc """
  Compte le nombre d'utilisateurs réguliers.

  Délégué à `Portfolio.Auth.UserService.count_regular_users/0`.
  """
  @spec count_regular_users() :: non_neg_integer()
  defdelegate count_regular_users(), to: UserService

  # =============================================================================
  # Magic Link API - Délégation à MagicLinkService
  # =============================================================================

  @doc """
  Demande un magic link pour un email donné.

  Délégué à `Portfolio.Auth.MagicLinkService.request_magic_link/1`.
  """
  @spec request_magic_link(String.t()) ::
          {:ok, MagicLink.t()}
          | {:error, Ecto.Changeset.t() | :user_not_found | {:rate_limit_exceeded, integer()}}
  defdelegate request_magic_link(email), to: MagicLinkService

  @doc """
  Demande un magic link pour un email donné en tant qu'admin (bypass rate limiting).

  Délégué à `Portfolio.Auth.MagicLinkService.request_magic_link_as_admin/1`.
  """
  @spec request_magic_link_as_admin(String.t()) ::
          {:ok, MagicLink.t()} | {:error, Ecto.Changeset.t() | :user_not_found}
  defdelegate request_magic_link_as_admin(email), to: MagicLinkService

  @doc """
  Vérifie un magic link par son token.

  Délégué à `Portfolio.Auth.MagicLinkService.verify_magic_link/1`.
  """
  @spec verify_magic_link(String.t()) ::
          {:ok, User.t()} | {:error, :invalid_token | :expired | :already_used}
  defdelegate verify_magic_link(token), to: MagicLinkService

  @doc """
  Supprime tous les magic links expirés.

  Délégué à `Portfolio.Auth.MagicLinkService.delete_expired_magic_links/0`.
  """
  @spec delete_expired_magic_links() :: {integer(), nil}
  defdelegate delete_expired_magic_links(), to: MagicLinkService

  @doc """
  Récupère un magic link par son code court.

  Délégué à `Portfolio.Auth.MagicLinkService.get_magic_link_by_short_code/1`.
  """
  @spec get_magic_link_by_short_code(String.t()) :: {:ok, MagicLink.t()} | {:error, :not_found}
  defdelegate get_magic_link_by_short_code(short_code), to: MagicLinkService

  # =============================================================================
  # Session API - Délégation à SessionService
  # =============================================================================

  @doc """
  Crée une nouvelle session pour un utilisateur.

  Délégué à `Portfolio.Auth.SessionService.create_session/1`.
  """
  @spec create_session(User.t()) :: {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_session(user), to: SessionService

  @doc """
  Récupère une session par son token.

  Délégué à `Portfolio.Auth.SessionService.get_session_by_token/1`.
  """
  @spec get_session_by_token(String.t()) :: UserSession.t() | nil
  defdelegate get_session_by_token(token), to: SessionService

  @doc """
  Récupère une session par son ID.

  Délégué à `Portfolio.Auth.SessionService.get_session!/1`.
  """
  @spec get_session!(Ecto.UUID.t()) :: UserSession.t()
  defdelegate get_session!(id), to: SessionService

  @doc """
  Liste toutes les sessions d'un utilisateur.

  Délégué à `Portfolio.Auth.SessionService.list_user_sessions/1`.
  """
  @spec list_user_sessions(Ecto.UUID.t()) :: [UserSession.t()]
  defdelegate list_user_sessions(user_id), to: SessionService

  @doc """
  Met à jour l'activité d'une session.

  Délégué à `Portfolio.Auth.SessionService.update_session_activity/1`.
  """
  @spec update_session_activity(UserSession.t()) ::
          {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_session_activity(session), to: SessionService

  @doc """
  Recharge le user d'une session depuis la base de données.

  Permet de récupérer les données fraîches du user (notamment le role)
  même si la session est mise en cache.

  Délégué à `Portfolio.Auth.SessionService.reload_user/1`.
  """
  @spec reload_user(UserSession.t()) :: UserSession.t()
  defdelegate reload_user(session), to: SessionService

  @doc """
  Supprime une session (logout).

  Délégué à `Portfolio.Auth.SessionService.delete_session/1`.
  """
  @spec delete_session(UserSession.t()) :: {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_session(session), to: SessionService

  @doc """
  Supprime toutes les sessions d'un utilisateur.

  Délégué à `Portfolio.Auth.SessionService.delete_all_user_sessions/1`.
  """
  @spec delete_all_user_sessions(User.t()) :: {integer(), nil}
  defdelegate delete_all_user_sessions(user), to: SessionService

  @doc """
  Supprime toutes les sessions d'un utilisateur sauf celle spécifiée.

  Délégué à `Portfolio.Auth.SessionService.delete_all_user_sessions_except/2`.
  """
  @spec delete_all_user_sessions_except(User.t(), Ecto.UUID.t()) :: {integer(), nil}
  defdelegate delete_all_user_sessions_except(user, current_session_id), to: SessionService

  @doc """
  Supprime toutes les sessions expirées.

  Délégué à `Portfolio.Auth.SessionService.delete_expired_sessions/0`.
  """
  @spec delete_expired_sessions() :: {integer(), nil}
  defdelegate delete_expired_sessions(), to: SessionService
end
