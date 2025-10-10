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
     |> assign(:filter, nil)}
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

  # Optimisation: filtrage en base de données au lieu de filtrer en mémoire
  defp load_users(nil), do: Auth.list_users()
  defp load_users("admin"), do: Auth.list_users(role: :admin)
  defp load_users("user"), do: Auth.list_users(role: :user)
  defp load_users(_), do: Auth.list_users()
end
