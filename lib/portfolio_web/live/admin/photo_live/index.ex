defmodule PortfolioWeb.Admin.PhotoLive.Index do
  @moduledoc """
  LiveView pour la liste des photos dans l'interface admin.

  Permet de :
  - Visualiser toutes les photos
  - Filtrer par album
  - Paginer les résultats
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Photography

  on_mount PortfolioWeb.LiveAuth

  @photos_per_page 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("admin.photos.title"))
     |> assign(:page, 1)
     |> assign(:per_page, @photos_per_page)
     |> assign(:album_filter, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(params["page"] || "1")
    album_filter = params["album"]

    photos = load_photos(page, socket.assigns.per_page, album_filter)
    total_photos = count_photos(album_filter)
    total_pages = ceil(total_photos / socket.assigns.per_page)
    albums = Photography.list_albums()

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:album_filter, album_filter)
     |> assign(:photos, photos)
     |> assign(:total_photos, total_photos)
     |> assign(:total_pages, total_pages)
     |> assign(:albums, albums)}
  end

  defp load_photos(page, per_page, album_filter) do
    offset = (page - 1) * per_page
    opts = [limit: per_page, offset: offset, preload: [:album], order_by: [desc: :inserted_at]]

    opts =
      if album_filter do
        Keyword.put(opts, :album_id, album_filter)
      else
        opts
      end

    Photography.list_photos(opts)
  end

  defp count_photos(nil), do: Photography.count_all_photos()

  defp count_photos(album_id) do
    Photography.count_photos_by_album(album_id)
  end

  defp pagination_range(current_page, total_pages) do
    max_pages = 7
    half = div(max_pages, 2)

    cond do
      total_pages <= max_pages ->
        1..total_pages

      current_page <= half + 1 ->
        1..max_pages

      current_page >= total_pages - half ->
        (total_pages - max_pages + 1)..total_pages

      true ->
        (current_page - half)..(current_page + half)
    end
  end

  defp build_params(album_filter, page) do
    params = []
    params = if album_filter, do: [{:album, album_filter} | params], else: params
    params = if page > 1, do: [{:page, page} | params], else: params
    URI.encode_query(params)
  end
end
