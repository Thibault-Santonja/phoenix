defmodule PortfolioWeb.PhotographyLive.Timeline do
  @moduledoc """
  LiveView module rendering the photography timeline page.

  This component displays a chronological archive of photo albums grouped by year,
  with a smooth scroll-based interaction that highlights the current year in the
  background as users navigate through the content.

  Key features:
  - Dynamic display of albums by year from database.
  - Year highlight transitions on scroll using IntersectionObserver.
  - Translated album titles and descriptions using Gettext.
  - Responsive design with Tailwind CSS grid layout.
  - Enhanced visual experience with custom CSS and animations.
  - Lightweight JavaScript hook (`YearTrigger`) for animated year switching.
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Photography

  @impl true
  def mount(_, session, socket) do
    locale = session["locale"] || "fr"
    Gettext.put_locale(PortfolioWeb.Gettext, locale)

    # Charger les albums depuis la DB
    db_albums = Photography.list_published_albums_by_year(preload: [:photos])

    # Convertir les albums DB au format attendu par le template
    timeline_data = convert_albums_to_timeline_format(db_albums)

    {:ok, assign(socket, :timeline_data, timeline_data)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {:noreply, push_event(socket, "change_locale", %{"locale" => locale})}
  end

  defp apply_action(socket, :index, %{"chapter" => chapter}) do
    timeline_data = socket.assigns[:timeline_data] || %{}
    data = filter_data(timeline_data, chapter)

    socket
    |> assign(:chapter, chapter)
    |> assign(:data, data)
    |> assign(years: data |> Map.keys() |> Enum.sort(:desc))
    |> assign(:page_title, build_title(chapter))
  end

  defp apply_action(socket, :index, _params) do
    timeline_data = socket.assigns[:timeline_data] || %{}

    socket
    |> assign(:chapter, nil)
    |> assign(:data, timeline_data)
    |> assign(years: timeline_data |> Map.keys() |> Enum.sort(:desc))
    |> assign(:page_title, gettext("photography.timeline.title"))
  end

  defp build_title(chapter) do
    gettext("photography.timeline.gallery_prefix") <> String.capitalize(chapter)
  end

  defp filter_data(data, chapter) do
    data
    |> Enum.map(fn {k, v} -> {k, Enum.filter(v, &(&1.type == chapter))} end)
    |> Enum.filter(fn {_k, v} -> not Enum.empty?(v) end)
    |> Map.new()
  end

  # Convertit les albums de la DB au format attendu par le template
  defp convert_albums_to_timeline_format(albums_by_year) do
    albums_by_year
    |> Enum.map(fn {year, albums} ->
      timeline_albums = Enum.map(albums, &album_to_timeline_item/1)
      {year, timeline_albums}
    end)
    |> Map.new()
  end

  defp album_to_timeline_item(album) do
    # Utiliser la première photo comme cover photo
    cover_photo = List.first(album.photos)

    # Construire la chaîne de date avec plage si date_fin existe
    date_str = format_date_range(album.date_prise_vue, album.date_fin_prise_vue)

    %{
      type: to_string(album.type),
      date: date_str,
      title: album.title,
      description: album.description || "",
      photography: if(cover_photo, do: cover_photo.file_path, else: nil),
      url: "/gallery/#{album.slug}",
      reference_link: album.reference_link
    }
  end

  # Formate une plage de dates pour l'affichage
  # Si date_fin est nulle, affiche seulement date_debut
  # Sinon, affiche "date_debut - date_fin"
  defp format_date_range(date_debut, nil), do: Date.to_iso8601(date_debut)

  defp format_date_range(date_debut, date_fin) do
    "#{Date.to_iso8601(date_debut)} - #{Date.to_iso8601(date_fin)}"
  end
end
