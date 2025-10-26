defmodule PortfolioWeb.Admin.AlbumLive.Index do
  @moduledoc """
  LiveView pour la liste des albums dans l'interface admin.

  Permet de :
  - Visualiser tous les albums avec leur statut
  - Créer un nouvel album
  - Éditer un album existant
  - Supprimer un album
  - Basculer le statut published d'un album
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Photography

  on_mount PortfolioWeb.LiveAuth

  @impl true
  def mount(_params, _session, socket) do
    # Lecture de la configuration pour le nombre d'albums par page
    albums_per_page = Application.get_env(:portfolio, :admin)[:albums_per_page] || 30
    {:ok,
     socket
     |> assign(:page_title, "Albums")
     |> assign(:filter, nil)
     |> assign(:page, 1)
     |> assign(:per_page, albums_per_page)
     |> assign(:sort_by, nil)
     |> assign(:sort_order, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filter = params["filter"]
    page = String.to_integer(params["page"] || "1")
    sort_by = params["sort_by"]
    sort_order = params["sort_order"]

    # Optimisation: calculer les statistiques une seule fois au lieu de 3x dans le template
    count_stats = %{
      all: Photography.count_all_albums(),
      published: Photography.count_published_albums(),
      draft: Photography.count_draft_albums()
    }

    # Calculer le nombre total d'albums pour la pagination
    total_albums =
      case filter do
        "draft" -> count_stats.draft
        "published" -> count_stats.published
        _ -> count_stats.all
      end

    total_pages = ceil(total_albums / socket.assigns.per_page)
    albums = load_albums(filter, page, socket.assigns.per_page, sort_by, sort_order)

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> assign(:page, page)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:total_pages, total_pages)
     |> assign(:total_albums, total_albums)
     |> assign(:albums, albums)
     |> assign(:count_stats, count_stats)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Albums")
  end

  # Composant pour un en-tête de colonne triable
  attr :column, :string, required: true
  attr :label, :string, required: true
  attr :current_sort_by, :string, required: true
  attr :current_sort_order, :string, required: true
  attr :filter, :string, default: nil

  defp sortable_header(assigns) do
    {next_sort_by, next_sort_order} =
      next_sort_state(assigns.column, assigns.current_sort_by, assigns.current_sort_order)

    assigns =
      assigns
      |> assign(:next_sort_by, next_sort_by)
      |> assign(:next_sort_order, next_sort_order)

    ~H"""
    <.link
      patch={~p"/admin/albums?#{build_params(@filter, 1, @next_sort_by, @next_sort_order)}"}
      class="group inline-flex items-center gap-1 hover:text-indigo-600"
    >
      <%= @label %>
      <span class="text-gray-400"><%= sort_icon(@column, @current_sort_by, @current_sort_order) %></span>
    </.link>
    """
  end

  # Recharge les albums en utilisant les paramètres actuels du socket
  defp reload_albums(socket) do
    load_albums(
      socket.assigns.filter,
      socket.assigns.page,
      socket.assigns.per_page,
      socket.assigns.sort_by,
      socket.assigns.sort_order
    )
  end

  # Optimisation: utiliser with_photo_count au lieu de preload toutes les photos
  # Pattern simplifié pour éviter la répétition
  defp load_albums(filter, page, per_page, sort_by, sort_order) do
    offset = (page - 1) * per_page
    opts = [with_photo_count: true, limit: per_page, offset: offset]

    opts =
      case filter do
        "draft" -> Keyword.put(opts, :published, false)
        "published" -> Keyword.put(opts, :published, true)
        _ -> opts
      end

    # Ajouter le tri (ordre par défaut : date décroissante)
    order_by =
      case {sort_by, sort_order} do
        {"title", "asc"} -> [asc: :title]
        {"title", "desc"} -> [desc: :title]
        {"type", "asc"} -> [asc: :type]
        {"type", "desc"} -> [desc: :type]
        {"date", "asc"} -> [asc: :date_prise_vue]
        {"date", "desc"} -> [desc: :date_prise_vue]
        {"photos", "asc"} -> [asc: :photo_count]
        {"photos", "desc"} -> [desc: :photo_count]
        {"published", "asc"} -> [asc: :published]
        {"published", "desc"} -> [desc: :published]
        # Ordre par défaut si aucun tri actif
        {nil, _} -> [desc: :date_prise_vue]
        _ -> [desc: :date_prise_vue]
      end

    opts = Keyword.put(opts, :order_by, order_by)

    Photography.list_albums(opts)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Photography.get_album(id) do
      {:ok, album} ->
        case Photography.delete_album(album) do
          {:ok, _result} ->
            {:noreply,
             socket
             |> put_flash(:info, "Album supprimé avec succès")
             |> assign(:albums, reload_albums(socket))}

          {:error, _reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Impossible de supprimer l'album")}
        end

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Album introuvable")
         |> assign(:albums, reload_albums(socket))}
    end
  end

  @impl true
  def handle_event("toggle_publish", %{"id" => id}, socket) do
    case Photography.get_album(id) do
      {:ok, album} ->
        case Photography.update_album(album, %{published: !album.published}) do
          {:ok, _album} ->
            {:noreply,
             socket
             |> put_flash(:info, "Statut de publication mis à jour")
             |> assign(:albums, reload_albums(socket))}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> put_flash(:error, "Impossible de mettre à jour le statut")}
        end

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Album introuvable")
         |> assign(:albums, reload_albums(socket))}
    end
  end

  # Fonction helper pour formater les types d'albums
  defp format_type(:couples), do: "Couples"
  defp format_type(:wedding), do: "Mariage"
  defp format_type(:motherhood), do: "Maternité"
  defp format_type(:events), do: "Événements"
  defp format_type(:landscape), do: "Paysage"
  defp format_type(:street), do: "Street"
  defp format_type(:music), do: "Musique"
  defp format_type(:reenactment), do: "Reconstitution"
  defp format_type(:amvcc), do: "AMVCC"
  defp format_type(:china), do: "Chine"
  defp format_type(:japan), do: "Japon"
  defp format_type(:taiwan), do: "Taïwan"
  defp format_type(type), do: to_string(type)

  # Fonction helper pour la pagination - génère la plage de numéros de page à afficher
  defp pagination_range(current_page, total_pages) do
    # Afficher au maximum 7 numéros de page
    max_pages = 7
    half = div(max_pages, 2)

    cond do
      # Si total <= max_pages, afficher tout
      total_pages <= max_pages ->
        1..total_pages

      # Si on est proche du début
      current_page <= half + 1 ->
        1..max_pages

      # Si on est proche de la fin
      current_page >= total_pages - half ->
        (total_pages - max_pages + 1)..total_pages

      # Sinon, centrer autour de la page actuelle
      true ->
        (current_page - half)..(current_page + half)
    end
  end

  # Fonction helper pour le badge de type
  defp type_badge_class(:wedding), do: "bg-pink-100 text-pink-800"
  defp type_badge_class(:couples), do: "bg-purple-100 text-purple-800"
  defp type_badge_class(:motherhood), do: "bg-blue-100 text-blue-800"
  defp type_badge_class(:events), do: "bg-green-100 text-green-800"
  defp type_badge_class(:landscape), do: "bg-emerald-100 text-emerald-800"
  defp type_badge_class(:street), do: "bg-gray-100 text-gray-800"
  defp type_badge_class(:music), do: "bg-indigo-100 text-indigo-800"
  defp type_badge_class(:reenactment), do: "bg-amber-100 text-amber-800"
  defp type_badge_class(:amvcc), do: "bg-red-100 text-red-800"
  defp type_badge_class(:china), do: "bg-yellow-100 text-yellow-800"
  defp type_badge_class(:japan), do: "bg-rose-100 text-rose-800"
  defp type_badge_class(:taiwan), do: "bg-cyan-100 text-cyan-800"
  defp type_badge_class(_), do: "bg-gray-100 text-gray-800"

  # Fonction helper pour construire les paramètres de pagination/navigation
  defp build_params(filter, page, sort_by, sort_order) do
    params = []
    params = if filter, do: [{:filter, filter} | params], else: params
    params = if page > 1, do: [{:page, page} | params], else: params
    params = if sort_by, do: [{:sort_by, sort_by} | params], else: params
    params = if sort_order, do: [{:sort_order, sort_order} | params], else: params
    params
  end

  # Cycle de tri à 3 états pour une colonne
  # Dates: desc → asc → none
  # Autres: asc → desc → none
  defp next_sort_state(column, current_sort_by, current_sort_order) do
    is_date_column = column == "date"

    cond do
      # Pas de tri actif OU tri sur une autre colonne
      current_sort_by != column or current_sort_by == nil ->
        if is_date_column do
          {column, "desc"}
        else
          {column, "asc"}
        end

      # Tri actif sur cette colonne
      current_sort_by == column ->
        case {is_date_column, current_sort_order} do
          # Date: desc → asc → none
          {true, "desc"} -> {column, "asc"}
          {true, "asc"} -> {nil, nil}
          # Autres: asc → desc → none
          {false, "asc"} -> {column, "desc"}
          {false, "desc"} -> {nil, nil}
          _ -> {nil, nil}
        end
    end
  end

  # Helper pour obtenir l'icône de tri à afficher
  defp sort_icon(column, current_sort_by, current_sort_order) do
    cond do
      current_sort_by == column and current_sort_order == "asc" ->
        "↑"

      current_sort_by == column and current_sort_order == "desc" ->
        "↓"

      true ->
        ""
    end
  end
end
