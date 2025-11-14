defmodule PortfolioWeb.UserAuth do
  @moduledoc """
  LiveView hooks pour l'authentification.

  Fournit des hooks `on_mount` pour gérer l'authentification dans les LiveViews.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias PortfolioWeb.AuthConfig
  alias PortfolioWeb.AuthHelpers

  @doc """
  Hook `on_mount` pour gérer l'authentification dans les LiveViews.

  Supporte trois modes:

  - `:mount_current_user` - Monte l'utilisateur courant (nil si non authentifié)
  - `:ensure_authenticated` - Exige l'authentification, redirige vers /login sinon
  - `:redirect_if_user_is_authenticated` - Redirige vers /admin si déjà authentifié

  ## Exemples

      # Pages publiques avec utilisateur optionnel
      live_session :current_user,
        on_mount: [{PortfolioWeb.UserAuth, :mount_current_user}] do
        live "/", PhotoLive.Index, :index
      end

      # Pages protégées
      live_session :require_authenticated_user,
        on_mount: [{PortfolioWeb.UserAuth, :ensure_authenticated}] do
        live "/admin", AdminLive.Index, :index
      end

      # Pages de login (redirige si déjà connecté)
      live_session :redirect_if_authenticated,
        on_mount: [{PortfolioWeb.UserAuth, :redirect_if_user_is_authenticated}] do
        live "/login", AuthLive.Login, :index
      end
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    socket = mount_current_user(socket, session)
    {:cont, socket}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, AuthConfig.unauthenticated_message())
        |> redirect(to: AuthConfig.login_path())

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, redirect(socket, to: AuthConfig.authenticated_path())}
    else
      {:cont, socket}
    end
  end

  # Fonction privée pour monter l'utilisateur courant dans le socket
  defp mount_current_user(socket, session) do
    # IMPORTANT: Utiliser une clé string "session_token" car Phoenix convertit
    # les clés de session en strings lors du passage à LiveView
    session_token = session["session_token"]

    case AuthHelpers.fetch_user_from_session_token(session_token) do
      nil ->
        assign(socket, :current_user, nil)

      {user, user_session} ->
        socket
        |> assign(:current_user, user)
        |> assign(:current_session, user_session)
    end
  end
end
