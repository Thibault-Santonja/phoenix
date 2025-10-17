defmodule PortfolioWeb.UserAuth do
  @moduledoc """
  LiveView hooks pour l'authentification.

  Fournit des hooks `on_mount` pour gérer l'authentification dans les LiveViews.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias Portfolio.Auth

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
        |> put_flash(:error, "Vous devez être connecté pour accéder à cette page.")
        |> redirect(to: "/login")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, redirect(socket, to: "/admin")}
    else
      {:cont, socket}
    end
  end

  # Fonction privée pour monter l'utilisateur courant dans le socket
  defp mount_current_user(socket, session) do
    case session["session_token"] do
      nil ->
        assign(socket, :current_user, nil)

      session_token ->
        case Auth.get_session_by_token(session_token) do
          nil ->
            assign(socket, :current_user, nil)

          user_session ->
            # Mettre à jour l'activité de la session
            Auth.update_session_activity(user_session)

            socket
            |> assign(:current_user, user_session.user)
            |> assign(:current_session, user_session)
        end
    end
  end
end
