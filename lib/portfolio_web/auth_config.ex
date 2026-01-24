defmodule PortfolioWeb.AuthConfig do
  @moduledoc """
  Configuration centralisée pour l'authentification.

  Ce module définit les constantes et messages utilisés par le système
  d'authentification pour éviter la duplication de strings hardcodés.

  ## Responsabilités

  - Messages d'erreur standardisés
  - Chemins de redirection
  - Configuration des rôles et permissions
  """

  @doc """
  Message d'erreur lorsqu'un utilisateur non authentifié tente d'accéder
  à une ressource protégée.
  """
  @spec unauthenticated_message() :: String.t()
  def unauthenticated_message do
    "Vous devez être connecté pour accéder à cette page."
  end

  @doc """
  Message d'erreur lorsqu'un utilisateur n'a pas les permissions nécessaires.
  """
  @spec unauthorized_message() :: String.t()
  def unauthorized_message do
    "Vous n'avez pas les permissions pour accéder à cette page."
  end

  @doc """
  Chemin de redirection pour les utilisateurs non authentifiés.
  """
  @spec login_path() :: String.t()
  def login_path, do: "/login"

  @doc """
  Chemin de redirection après authentification réussie.
  """
  @spec authenticated_path() :: String.t()
  def authenticated_path, do: "/admin"

  @doc """
  Chemin de redirection par défaut pour les utilisateurs sans permissions.
  """
  @spec unauthorized_path() :: String.t()
  def unauthorized_path, do: "/"

  @doc """
  Liste des rôles ayant accès à l'administration.
  """
  @spec admin_roles() :: [:admin, ...]
  def admin_roles, do: [:admin]

  @doc """
  Vérifie si un rôle a les permissions d'administration.

  ## Exemples

      iex> AuthConfig.admin_role?(:admin)
      true

      iex> AuthConfig.admin_role?(:user)
      false
  """
  @spec admin_role?(atom() | nil) :: boolean()
  def admin_role?(role) when is_atom(role) do
    role in admin_roles()
  end

  def admin_role?(_), do: false
end
