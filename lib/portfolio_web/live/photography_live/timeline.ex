defmodule PortfolioWeb.PhotographyLive.Timeline do
  @moduledoc """
  LiveView module rendering the photography timeline page.

  This component displays a chronological archive of photo albums grouped by year,
  with a smooth scroll-based interaction that highlights the current year in the
  background as users navigate through the content.

  Key features:
  - Dynamic display of albums by year from database.
  - Lazy loading with infinite scroll for optimal performance.
  - Year highlight transitions on scroll using IntersectionObserver.
  - Translated album titles and descriptions using Gettext.
  - Responsive design with Tailwind CSS grid layout.
  - Enhanced visual experience with custom CSS and animations.
  - Lightweight JavaScript hooks (`YearTrigger`, `InfiniteScroll`) for UX.
  """

  use PortfolioWeb, :live_view
  import PortfolioWeb.SEO.ImageHelpers
  import PortfolioWeb.SEO.SchemaHelpers

  alias Portfolio.Photography

  @albums_per_page Application.compile_env(:portfolio, [:timeline, :albums_per_page], 20)

  # Valid album types for chapter filtering (must match Album.@album_types)
  @valid_chapter_types ~w(couples wedding motherhood events landscape street music reenactment amvcc china japan taiwan)

  @impl true
  def mount(_, session, socket) do
    locale = session["locale"] || "fr"
    _ = Gettext.put_locale(PortfolioWeb.Gettext, locale)

    # Load list of years for navigation (lightweight query)
    years = Photography.list_published_years()

    # Generate breadcrumb schema for timeline
    breadcrumb_json = generate_timeline_breadcrumb_schema()

    socket =
      socket
      |> assign(:years, years)
      |> assign(:page, 1)
      |> assign(:has_more, true)
      |> assign(:albums_loaded, 0)
      |> assign(:breadcrumb_json, breadcrumb_json)
      |> stream(:albums, [])

    # Load initial page of albums if connected
    socket =
      if connected?(socket) do
        load_albums(socket, 1)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {:noreply, push_event(socket, "change_locale", %{"locale" => locale})}
  end

  @impl true
  def handle_event("load_more", _, socket) do
    if socket.assigns.has_more do
      next_page = socket.assigns.page + 1
      {:noreply, load_albums(socket, next_page)}
    else
      {:noreply, socket}
    end
  end

  defp apply_action(socket, :index, %{"chapter" => chapter}) do
    socket
    |> assign(:chapter, chapter)
    |> assign(:page_title, build_title(chapter))
    |> assign(:page, 1)
    |> assign(:has_more, true)
    |> assign(:albums_loaded, 0)
    |> stream(:albums, [], reset: true)
    |> load_albums(1)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:chapter, nil)
    |> assign(:page_title, gettext("photography.timeline.title"))
  end

  defp build_title(chapter) do
    gettext("photography.timeline.gallery_prefix") <> String.capitalize(chapter)
  end

  # Load albums with pagination
  defp load_albums(socket, page) do
    chapter_filter = Map.get(socket.assigns, :chapter)
    offset = (page - 1) * @albums_per_page

    opts = [
      published: true,
      preload: [:photos],
      limit: @albums_per_page + 1,
      offset: offset
    ]

    opts =
      if chapter_filter && chapter_filter in @valid_chapter_types do
        Keyword.put(opts, :type, String.to_existing_atom(chapter_filter))
      else
        opts
      end

    albums = Photography.list_albums(opts)

    # Check if there are more albums to load
    {albums_to_show, has_more} =
      if length(albums) > @albums_per_page do
        {Enum.take(albums, @albums_per_page), true}
      else
        {albums, false}
      end

    # Track total albums loaded for empty state
    current_count = socket.assigns[:albums_loaded] || 0
    new_count = current_count + length(albums_to_show)

    socket
    |> assign(:page, page)
    |> assign(:has_more, has_more)
    |> assign(:albums_loaded, new_count)
    |> stream(:albums, albums_to_show)
  end

  # Formate une plage de dates pour l'affichage
  # Si date_fin est nulle, affiche seulement date_debut
  # Sinon, affiche "date_debut - date_fin"
  defp format_date_range(date_debut, nil), do: Date.to_iso8601(date_debut)

  defp format_date_range(date_debut, date_fin) do
    "#{Date.to_iso8601(date_debut)} - #{Date.to_iso8601(date_fin)}"
  end

  defp generate_timeline_breadcrumb_schema do
    breadcrumbs = [
      %{name: "Home", url: "https://photo.thibaultsan.com"},
      %{name: "Timeline", url: "https://photo.thibaultsan.com/timeline"}
    ]

    breadcrumb_schema(breadcrumbs)
  end
end
