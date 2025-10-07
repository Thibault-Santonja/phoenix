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

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> assign(:users, users)}
  end

  defp load_users(nil), do: Auth.list_users()

  defp load_users("admin") do
    Auth.list_users()
    |> Enum.filter(&(&1.role == :admin))
  end

  defp load_users("user") do
    Auth.list_users()
    |> Enum.filter(&(&1.role == :user))
  end

  defp load_users(_), do: Auth.list_users()
end
