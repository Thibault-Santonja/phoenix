defmodule PortfolioWeb.Plugs.RequireAuth do
  @moduledoc """
  Plugs pour l'authentification et l'autorisation.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias PortfolioWeb.AuthConfig
  alias PortfolioWeb.AuthHelpers

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, :fetch_current_user), do: fetch_current_user(conn, [])
  def call(conn, :require_authenticated_user), do: require_authenticated_user(conn, [])
  def call(conn, :require_admin_role), do: require_admin_role(conn, [])

  def call(conn, :redirect_if_user_is_authenticated),
    do: redirect_if_user_is_authenticated(conn, [])

  @doc """
  Récupère l'utilisateur courant depuis le token de session avec cache.

  Vérifie que:
  - Le token de session existe en base de données (ou dans le cache)
  - La session n'a pas expiré (30 jours d'inactivité)
  - Met à jour l'activité de la session pour prolonger sa durée

  Utilise Cachex pour mettre en cache les sessions pendant 1 heure et éviter
  les requêtes DB répétées. Le cache est invalidé lors du logout.

  Assigne `conn.assigns.current_user` si un utilisateur est connecté.
  """
  def fetch_current_user(conn, _opts) do
    # Si current_user est déjà assigné (ex: juste après login), ne pas refetch
    if conn.assigns[:current_user] do
      conn
    else
      fetch_user_from_session(conn)
    end
  end

  # Récupère l'utilisateur depuis le token de session
  defp fetch_user_from_session(conn) do
    session_token = get_session(conn, :session_token)

    case AuthHelpers.fetch_user_from_session_token(session_token) do
      nil ->
        conn
        |> clear_session()
        |> assign(:current_user, nil)

      {user, session} ->
        conn
        |> assign(:current_user, user)
        |> assign(:current_session, session)
    end
  end

  @doc """
  Exige qu'un utilisateur soit authentifié.

  Redirige vers le chemin de login si aucun utilisateur n'est connecté.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, AuthConfig.unauthenticated_message())
      |> redirect(to: AuthConfig.login_path())
      |> halt()
    end
  end

  @doc """
  Exige que l'utilisateur ait le rôle admin.

  Redirige vers le chemin par défaut si l'utilisateur n'a pas les permissions.
  """
  def require_admin_role(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && AuthConfig.admin_role?(user.role) do
      conn
    else
      conn
      |> put_flash(:error, AuthConfig.unauthorized_message())
      |> redirect(to: AuthConfig.unauthorized_path())
      |> halt()
    end
  end

  @doc """
  Redirige les utilisateurs déjà authentifiés.

  Utile pour les pages de login/register qui ne devraient être accessibles
  qu'aux utilisateurs non connectés.

  Redirige vers le chemin authentifié si l'utilisateur est déjà connecté.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: AuthConfig.authenticated_path())
      |> halt()
    else
      conn
    end
  end
end
