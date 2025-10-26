defmodule PortfolioWeb.Admin.UserLive.Index do
  @moduledoc """
  LiveView pour la liste des utilisateurs dans l'interface admin.

  Permet de :
  - Visualiser tous les utilisateurs
  - Voir les informations de chaque utilisateur (email, rôle, dates)
  - Filtrer et rechercher des utilisateurs
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Auth

  on_mount PortfolioWeb.LiveAuth

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Utilisateurs")
     |> assign(:filter, nil)
     |> assign(:edit_user, nil)
     |> assign(:delete_user_id, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filter = params["filter"]
    users = load_users(filter)

    # Optimisation: calculer les statistiques une seule fois au lieu de 2x dans le template
    user_stats = %{
      total: Auth.count_users(),
      admins: Auth.count_admin_users(),
      regular_users: Auth.count_regular_users()
    }

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> assign(:users, users)
     |> assign(:user_stats, user_stats)}
  end

  @impl true
  def handle_event("open_edit_modal", %{"user-id" => user_id}, socket) do
    user = Enum.find(socket.assigns.users, &(&1.id == user_id))
    {:noreply, assign(socket, edit_user: user)}
  end

  @impl true
  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, edit_user: nil)}
  end

  @impl true
  def handle_event("save_user", %{"user" => user_params}, socket) do
    case Auth.update_user_as_admin(socket.assigns.edit_user, user_params) do
      {:ok, _user} ->
        users = load_users(socket.assigns.filter)

        {:noreply,
         socket
         |> put_flash(:info, "Utilisateur mis à jour avec succès")
         |> assign(:edit_user, nil)
         |> assign(:users, users)}

      {:error, %Ecto.Changeset{} = _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Erreur lors de la mise à jour de l'utilisateur")}
    end
  end

  @impl true
  def handle_event("confirm_delete", %{"user-id" => user_id}, socket) do
    {:noreply, assign(socket, delete_user_id: user_id)}
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, delete_user_id: nil)}
  end

  @impl true
  def handle_event("delete_user", %{"user-id" => user_id}, socket) do
    user = Enum.find(socket.assigns.users, &(&1.id == user_id))

    case Auth.delete_user(user) do
      {:ok, _user} ->
        users = load_users(socket.assigns.filter)

        user_stats = %{
          total: Auth.count_users(),
          admins: Auth.count_admin_users(),
          regular_users: Auth.count_regular_users()
        }

        {:noreply,
         socket
         |> put_flash(:info, "Utilisateur supprimé avec succès")
         |> assign(:delete_user_id, nil)
         |> assign(:users, users)
         |> assign(:user_stats, user_stats)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Erreur lors de la suppression de l'utilisateur")
         |> assign(:delete_user_id, nil)}
    end
  end

  @impl true
  def handle_event("revoke_sessions", %{"user-id" => user_id}, socket) do
    user = Enum.find(socket.assigns.users, &(&1.id == user_id))
    {count, _} = Auth.delete_all_user_sessions(user)

    {:noreply,
     socket
     |> put_flash(:info, "#{count} session(s) révoquée(s) avec succès")}
  end

  # Optimisation: filtrage en base de données au lieu de filtrer en mémoire
  # Pattern simplifié
  defp load_users(filter) do
    case filter do
      "admin" -> Auth.list_users(role: :admin)
      "user" -> Auth.list_users(role: :user)
      _ -> Auth.list_users()
    end
  end
end
