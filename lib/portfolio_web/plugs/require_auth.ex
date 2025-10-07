defmodule PortfolioWeb.Plugs.RequireAuth do
  @moduledoc """
  Plugs pour l'authentification et l'autorisation.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Portfolio.Auth

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, :fetch_current_user), do: fetch_current_user(conn, [])
  def call(conn, :require_authenticated_user), do: require_authenticated_user(conn, [])
  def call(conn, :require_admin_role), do: require_admin_role(conn, [])

  @doc """
  Récupère l'utilisateur courant depuis le token de session.

  Vérifie que:
  - Le token de session existe en base de données
  - La session n'a pas expiré (30 jours d'inactivité)
  - Met à jour l'activité de la session pour prolonger sa durée

  Assigne `conn.assigns.current_user` si un utilisateur est connecté.
  """
  def fetch_current_user(conn, _opts) do
    session_token = get_session(conn, :session_token)

    if session_token do
      case Auth.get_session_by_token(session_token) do
        nil ->
          # Session invalide ou expirée
          conn
          |> clear_session()
          |> assign(:current_user, nil)

        session ->
          # Mettre à jour l'activité de la session
          Auth.update_session_activity(session)

          conn
          |> assign(:current_user, session.user)
          |> assign(:current_session, session)
      end
    else
      assign(conn, :current_user, nil)
    end
  end

  @doc """
  Exige qu'un utilisateur soit authentifié.

  Redirige vers /login si aucun utilisateur n'est connecté.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Vous devez être connecté pour accéder à cette page.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  @doc """
  Exige que l'utilisateur ait le rôle admin ou superadmin.

  Redirige vers / si l'utilisateur n'a pas les permissions.
  """
  def require_admin_role(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && user.role in [:admin, :superadmin] do
      conn
    else
      conn
      |> put_flash(:error, "Vous n'avez pas les permissions pour accéder à cette page.")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
