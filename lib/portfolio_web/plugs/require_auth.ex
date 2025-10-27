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
      session_token = get_session(conn, :session_token)

      if session_token do
        case fetch_session_from_cache(session_token) do
          nil ->
            # Session invalide ou expirée - effacer le token
            conn
            |> clear_session()
            |> assign(:current_user, nil)

          session ->
            # Mettre à jour l'activité de la session
            # Async en production pour ne pas ralentir la requête, sync en test pour la prévisibilité
            if Mix.env() == :test do
              Auth.update_session_activity(session)
            else
              Task.start(fn -> Auth.update_session_activity(session) end)
            end

            conn
            |> assign(:current_user, session.user)
            |> assign(:current_session, session)
        end
      else
        assign(conn, :current_user, nil)
      end
    end
  end

  # Récupère une session depuis le cache ou la base de données
  defp fetch_session_from_cache(session_token) do
    cache_key = {:session, session_token}

    # En test, skip le cache pour éviter la pollution entre tests
    if Mix.env() == :test do
      Auth.get_session_by_token(session_token)
    else
      case Cachex.fetch(:portfolio_cache, cache_key, fn ->
             case Auth.get_session_by_token(session_token) do
               nil ->
                 # Session invalide, ne pas mettre en cache
                 {:ignore, nil}

               session ->
                 # Cacher la session pendant 1 heure
                 {:commit, session, ttl: :timer.hours(1)}
             end
           end) do
        {:ok, session} -> session
        {:commit, session} -> session
        {:ignore, nil} -> nil
        _ -> nil
      end
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

  @doc """
  Redirige les utilisateurs déjà authentifiés.

  Utile pour les pages de login/register qui ne devraient être accessibles
  qu'aux utilisateurs non connectés.

  Redirige vers /admin si l'utilisateur est déjà connecté.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: "/admin")
      |> halt()
    else
      conn
    end
  end
end
