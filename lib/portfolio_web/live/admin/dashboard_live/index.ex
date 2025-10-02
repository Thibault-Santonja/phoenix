defmodule PortfolioWeb.Admin.DashboardLive.Index do
  @moduledoc """
  LiveView pour le tableau de bord administrateur.

  Page d'accueil de l'interface admin affichant :
  - Statistiques clés (albums, photos, utilisateurs)
  - Liens rapides vers les sections admin
  - Informations du profil utilisateur
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Photography
  alias Portfolio.Auth

  on_mount PortfolioWeb.LiveAuth

  @impl true
  def mount(_params, _session, socket) do
    stats = load_statistics()
    current_user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Tableau de bord")
     |> assign(:stats, stats)
     |> assign(:current_user, current_user)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  defp load_statistics do
    albums = Photography.list_albums()
    published_albums = Enum.filter(albums, & &1.published)

    total_photos =
      albums
      |> Enum.map(&Photography.count_photos_in_album(&1.id))
      |> Enum.sum()

    %{
      total_albums: length(albums),
      published_albums: length(published_albums),
      draft_albums: length(albums) - length(published_albums),
      total_photos: total_photos,
      total_users: Auth.count_users()
    }
  end
end
