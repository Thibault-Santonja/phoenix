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
  Récupère l'utilisateur courant depuis la session.

  Assigne `conn.assigns.current_user` si un utilisateur est connecté.
  """
  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)

    if user_id do
      case Auth.get_user(user_id) do
        nil ->
          conn
          |> clear_session()
          |> assign(:current_user, nil)

        user ->
          assign(conn, :current_user, user)
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

    if user && user.role in ["admin", "superadmin"] do
      conn
    else
      conn
      |> put_flash(:error, "Vous n'avez pas les permissions pour accéder à cette page.")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
