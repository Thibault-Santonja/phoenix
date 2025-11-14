defmodule PortfolioWeb.Admin.ProfileLive.Edit do
  @moduledoc """
  LiveView pour la gestion du profil utilisateur.

  Permet à l'utilisateur de :
  - Modifier son nom
  - Voir son email et rôle (lecture seule)
  - Gérer ses sessions actives
  - Révoquer des sessions spécifiques ou toutes les autres sessions
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Auth

  on_mount PortfolioWeb.LiveAuth

  @impl true
  def mount(_params, session, socket) do
    # current_user est assigné par le hook LiveAuth
    user = socket.assigns[:current_user]

    if user do
      sessions = Auth.list_user_sessions(user.id)

      # Récupérer la session actuelle depuis le token de session
      session_token = session["session_token"]
      current_session = if session_token, do: Auth.get_session_by_token(session_token), else: nil

      {:ok,
       socket
       |> assign(:page_title, gettext("admin.profile.title"))
       |> assign(:user, user)
       |> assign(:sessions, sessions)
       |> assign(:current_session, current_session)
       |> assign(:form, to_form(Auth.change_user(user)))}
    else
      # Si pas d'utilisateur connecté, rediriger vers login
      {:ok,
       socket
       |> put_flash(:error, gettext("admin.profile.login_required"))
       |> redirect(to: ~p"/login")}
    end
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Auth.update_user(socket.assigns.user, user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("admin.profile.update_success"))
         |> assign(:user, user)
         |> assign(:form, to_form(Auth.change_user(user)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("revoke_session", %{"id" => session_id}, socket) do
    session = Auth.get_session!(session_id)
    {:ok, _} = Auth.delete_session(session)

    {:noreply,
     socket
     |> put_flash(:info, gettext("admin.profile.session_revoked"))
     |> assign(:sessions, Auth.list_user_sessions(socket.assigns.user.id))}
  end

  @impl true
  def handle_event("revoke_all_sessions", _params, socket) do
    current_session = socket.assigns.current_session
    user = socket.assigns.user

    # Révoquer toutes sauf la session actuelle
    {count, _} = Auth.delete_all_user_sessions_except(user, current_session.id)

    {:noreply,
     socket
     |> put_flash(:info, gettext("admin.profile.sessions_revoked", count: count))
     |> assign(:sessions, Auth.list_user_sessions(user.id))}
  end
end
