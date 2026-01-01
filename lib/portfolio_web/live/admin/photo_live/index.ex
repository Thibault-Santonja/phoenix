defmodule PortfolioWeb.Admin.PhotoLive.Index do
  @moduledoc """
  LiveView pour la liste des photos dans l'interface admin.

  Permet de :
  - Visualiser toutes les photos
  - Filtrer par album
  - Paginer les résultats

  Utilise LiveView streams pour une gestion mémoire optimisée (LV-006).
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Photography
  alias PortfolioWeb.Helpers.PaginationHelper

  on_mount PortfolioWeb.LiveAuth

  @photos_per_page 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("admin.photos.title"))
     |> assign(:page, 1)
     |> assign(:per_page, @photos_per_page)
     |> assign(:album_filter, nil)
     |> assign(:photos_empty?, true)
     |> stream(:photos, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = PaginationHelper.parse_page(params["page"])
    album_filter = params["album"]

    photos = load_photos(page, socket.assigns.per_page, album_filter)
    total_photos = count_photos(album_filter)
    total_pages = PaginationHelper.total_pages(total_photos, socket.assigns.per_page)
    albums = Photography.list_albums()

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:album_filter, album_filter)
     |> assign(:photos_empty?, Enum.empty?(photos))
     |> assign(:total_photos, total_photos)
     |> assign(:total_pages, total_pages)
     |> assign(:albums, albums)
     |> stream(:photos, photos, reset: true)}
  end

  defp load_photos(page, per_page, album_filter) do
    opts =
      PaginationHelper.build_opts(page, per_page,
        extra: [preload: [:album], order_by: [desc: :inserted_at]]
      )

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

  defp build_params(album_filter, page) do
    params = []
    params = if album_filter, do: [{:album, album_filter} | params], else: params
    params = if page > 1, do: [{:page, page} | params], else: params
    URI.encode_query(params)
  end
end
