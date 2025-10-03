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
    users = Auth.list_users()

    {:ok,
     socket
     |> assign(:page_title, "Utilisateurs")
     |> assign(:users, users)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end
end
