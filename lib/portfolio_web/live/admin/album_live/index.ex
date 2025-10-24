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

  # Pagination : 25 albums par page
  @albums_per_page 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Albums")
     |> assign(:filter, nil)
     |> assign(:page, 1)
     |> assign(:per_page, @albums_per_page)
     |> assign(:sort_by, "date")
     |> assign(:sort_order, "desc")
     |> assign(:loading_action, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filter = params["filter"]
    page = String.to_integer(params["page"] || "1")
    sort_by = params["sort_by"] || "date"
    sort_order = params["sort_order"] || "desc"

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

    # Ajouter le tri
    order_by =
      case {sort_by, sort_order} do
        {"title", "asc"} -> [asc: :title]
        {"title", "desc"} -> [desc: :title]
        {"date", "asc"} -> [asc: :date_prise_vue]
        {"date", "desc"} -> [desc: :date_prise_vue]
        _ -> [desc: :date_prise_vue]
      end

    opts = Keyword.put(opts, :order_by, order_by)

    Photography.list_albums(opts)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    album = Photography.get_album!(id)

    case Photography.delete_album(album) do
      {:ok, _album} ->
        albums =
          load_albums(
            socket.assigns.filter,
            socket.assigns.page,
            socket.assigns.per_page,
            socket.assigns.sort_by,
            socket.assigns.sort_order
          )

        {:noreply,
         socket
         |> put_flash(:info, "Album supprimé avec succès")
         |> assign(:albums, albums)
         |> assign(:loading_action, nil)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Impossible de supprimer l'album")
         |> assign(:loading_action, nil)}
    end
  end

  @impl true
  def handle_event("toggle_publish", %{"id" => id}, socket) do
    album = Photography.get_album!(id)

    case Photography.update_album(album, %{published: !album.published}) do
      {:ok, _album} ->
        albums =
          load_albums(
            socket.assigns.filter,
            socket.assigns.page,
            socket.assigns.per_page,
            socket.assigns.sort_by,
            socket.assigns.sort_order
          )

        {:noreply,
         socket
         |> put_flash(:info, "Statut de publication mis à jour")
         |> assign(:albums, albums)
         |> assign(:loading_action, nil)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Impossible de mettre à jour le statut")
         |> assign(:loading_action, nil)}
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

  # Fonction helper pour construire les paramètres de tri
  defp build_sort_params(filter, page, sort_by, sort_order) do
    params = [sort_by: sort_by, sort_order: sort_order]
    params = if filter, do: [{:filter, filter} | params], else: params
    params = if page > 1, do: [{:page, page} | params], else: params
    URI.encode_query(params)
  end

  # Fonction helper pour basculer l'ordre de tri
  defp toggle_order(current_sort_by, current_sort_order, clicked_sort_by) do
    if current_sort_by == clicked_sort_by do
      if current_sort_order == "asc", do: "desc", else: "asc"
    else
      # Si on clique sur un nouveau tri, commencer par descendant pour les dates, ascendant pour les titres
      if clicked_sort_by == "date", do: "desc", else: "asc"
    end
  end

  # Fonction helper pour construire les paramètres de pagination
  defp build_pagination_params(filter, page, sort_by, sort_order) do
    params = []
    params = if filter, do: [{:filter, filter} | params], else: params
    params = if page > 1, do: [{:page, page} | params], else: params
    params = if sort_by != "date", do: [{:sort_by, sort_by} | params], else: params
    params = if sort_order != "desc", do: [{:sort_order, sort_order} | params], else: params
    URI.encode_query(params)
  end
end
