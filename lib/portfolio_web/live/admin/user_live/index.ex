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
  alias Portfolio.Auth.AuditLogger

  on_mount PortfolioWeb.LiveAuth

  # Valid roles for user role changes (must match User schema)
  @valid_roles ~w(admin user)

  @impl true
  def mount(_params, _session, socket) do
    # Stocker l'IP address dans les assigns pour l'audit logging
    ip_address =
      case get_connect_params(socket) do
        %{"peer_data" => %{"address" => address}} -> address
        _ -> nil
      end

    {:ok,
     socket
     |> assign(:page_title, gettext("admin.users.title"))
     |> assign(:filter, nil)
     |> assign(:edit_user, nil)
     |> assign(:delete_user_id, nil)
     |> assign(:ip_address, ip_address)}
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
    current_user_id = socket.assigns.current_user.id
    edit_user = socket.assigns.edit_user

    case Auth.update_user_as_admin(edit_user, user_params, current_user_id: current_user_id) do
      {:ok, updated_user} ->
        # Log audit si le rôle a changé
        new_role = user_params["role"]

        _audit_result =
          if new_role && to_string(edit_user.role) != new_role && new_role in @valid_roles do
            AuditLogger.log_user_role_changed(
              updated_user,
              old_role: edit_user.role,
              new_role: String.to_existing_atom(new_role),
              performed_by_id: current_user_id,
              ip_address: socket.assigns.ip_address,
              metadata: %{"via" => "admin_interface"}
            )
          end

        users = load_users(socket.assigns.filter)

        {:noreply,
         socket
         |> put_flash(:info, gettext("admin.users.update_success"))
         |> assign(:edit_user, nil)
         |> assign(:users, users)}

      {:error, %Ecto.Changeset{} = changeset} ->
        # Extraire le message d'erreur pour l'afficher
        error_message =
          if changeset.errors[:role] do
            elem(changeset.errors[:role], 0)
          else
            gettext("admin.users.update_error")
          end

        {:noreply,
         socket
         |> put_flash(:error, error_message)}
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
    current_user_id = socket.assigns.current_user.id

    case Auth.delete_user(user) do
      {:ok, deleted_user} ->
        # Log audit de la suppression
        _audit_result =
          AuditLogger.log_user_deleted(
            deleted_user,
            performed_by_id: current_user_id,
            ip_address: socket.assigns.ip_address,
            metadata: %{"via" => "admin_interface"}
          )

        users = load_users(socket.assigns.filter)

        user_stats = %{
          total: Auth.count_users(),
          admins: Auth.count_admin_users(),
          regular_users: Auth.count_regular_users()
        }

        {:noreply,
         socket
         |> put_flash(:info, gettext("admin.users.delete_success"))
         |> assign(:delete_user_id, nil)
         |> assign(:users, users)
         |> assign(:user_stats, user_stats)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("admin.users.delete_error"))
         |> assign(:delete_user_id, nil)}
    end
  end

  @impl true
  def handle_event("revoke_sessions", %{"user-id" => user_id}, socket) do
    user = Enum.find(socket.assigns.users, &(&1.id == user_id))
    current_user_id = socket.assigns.current_user.id
    {count, _} = Auth.delete_all_user_sessions(user)

    # Log audit de la révocation
    _audit_result =
      AuditLogger.log_sessions_revoked(
        user,
        session_count: count,
        performed_by_id: current_user_id,
        ip_address: socket.assigns.ip_address,
        metadata: %{"via" => "admin_interface"}
      )

    {:noreply,
     socket
     |> put_flash(:info, gettext("admin.users.sessions_revoked", count: count))}
  end

  @impl true
  def handle_event("send_magic_link", %{"user-id" => user_id}, socket) do
    user = Enum.find(socket.assigns.users, &(&1.id == user_id))
    current_user_id = socket.assigns.current_user.id

    # Utiliser la fonction admin qui bypass le rate limiting
    case Auth.request_magic_link_as_admin(user.email) do
      {:ok, _magic_link} ->
        # Log audit de l'envoi
        _audit_result =
          AuditLogger.log_magic_link_sent(
            user,
            performed_by_id: current_user_id,
            ip_address: socket.assigns.ip_address,
            metadata: %{"via" => "admin_interface", "bypass_rate_limit" => true}
          )

        {:noreply,
         socket
         |> put_flash(:info, gettext("admin.users.magic_link_sent", email: user.email))}

      {:error, :user_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("admin.users.user_not_found"))}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("admin.users.magic_link_error"))}
    end
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
