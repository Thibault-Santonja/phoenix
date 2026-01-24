defmodule PortfolioWeb.Admin.DashboardLive.Index do
  @moduledoc """
  LiveView pour le tableau de bord administrateur.

  Page d'accueil de l'interface admin affichant :
  - Statistiques clés (albums, photos, utilisateurs)
  - Liens rapides vers les sections admin
  - Informations du profil utilisateur
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Auth
  alias Portfolio.Photography
  alias PortfolioWeb.Helpers.TimeFormatter

  on_mount PortfolioWeb.LiveAuth

  @impl true
  def mount(_params, _session, socket) do
    stats = load_statistics()
    processing_stats = load_processing_statistics()
    current_user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, gettext("admin.dashboard.title"))
     |> assign(:stats, stats)
     |> assign(:processing_stats, processing_stats)
     |> assign(:current_user, current_user)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("retry_all_failed", _params, socket) do
    {:ok, count} = Photography.reprocess_all_failed_photos()
    processing_stats = load_processing_statistics()

    {:noreply,
     socket
     |> assign(:processing_stats, processing_stats)
     |> put_flash(:info, gettext("admin.dashboard.photos_restarted", count: count))}
  end

  defp load_statistics do
    # Optimization: Single SQL query for all album stats (avoids N+1)
    album_stats = Photography.get_album_stats()

    %{
      total_albums: album_stats.total,
      published_albums: album_stats.published,
      draft_albums: album_stats.draft,
      total_photos: Photography.count_all_photos(),
      total_users: Auth.count_users()
    }
  end

  defp load_processing_statistics do
    stats = Photography.get_processing_stats()
    storage_gb = Photography.get_storage_usage(unit: :gb)
    failed_photos = Photography.list_failed_photos(limit: 10, preload: [:album])

    oldest_pending =
      case Photography.get_oldest_pending_photo() do
        {:ok, photo} -> photo
        {:error, :not_found} -> nil
      end

    %{
      stats: stats,
      storage_gb: Float.round(storage_gb, 2),
      storage_capacity_gb: 30,
      storage_percentage: Float.round(storage_gb / 30 * 100, 1),
      failed_photos: failed_photos,
      oldest_pending: oldest_pending
    }
  end

  # Delegates to TimeFormatter for human-readable "time ago" strings
  defp time_ago(datetime), do: TimeFormatter.time_ago(datetime)
end
