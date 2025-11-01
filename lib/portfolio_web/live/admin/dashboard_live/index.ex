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

  on_mount PortfolioWeb.LiveAuth

  @impl true
  def mount(_params, _session, socket) do
    stats = load_statistics()
    processing_stats = load_processing_statistics()
    current_user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Tableau de bord")
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
     |> put_flash(:info, "#{count} photo(s) relancée(s) avec succès")}
  end

  defp load_statistics do
    albums = Photography.list_albums()
    published_albums = Enum.filter(albums, & &1.published)

    # Optimisation: une seule requête SQL au lieu de N requêtes
    total_photos = Photography.count_all_photos()

    %{
      total_albums: length(albums),
      published_albums: length(published_albums),
      draft_albums: length(albums) - length(published_albums),
      total_photos: total_photos,
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

  # Formats a DateTime into a human-readable "time ago" string
  defp time_ago(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 ->
        "#{diff_seconds} seconde#{if diff_seconds > 1, do: "s", else: ""}"

      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        "#{minutes} minute#{if minutes > 1, do: "s", else: ""}"

      diff_seconds < 86400 ->
        hours = div(diff_seconds, 3600)
        "#{hours} heure#{if hours > 1, do: "s", else: ""}"

      diff_seconds < 2_592_000 ->
        days = div(diff_seconds, 86400)
        "#{days} jour#{if days > 1, do: "s", else: ""}"

      true ->
        months = div(diff_seconds, 2_592_000)
        "#{months} mois"
    end
  end
end
