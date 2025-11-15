defmodule PortfolioWeb.PhotographyLive.Gallery do
  use PortfolioWeb, :live_view
  import PortfolioWeb.Components.ThemeButton
  import PortfolioWeb.SEO.ImageHelpers
  import PortfolioWeb.SEO.SchemaHelpers

  alias Portfolio.Photography

  @default_data [
    %{
      title: gettext("photography.gallery.china_title"),
      description:
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
      photo_url: "/images/photography/china.webp"
    },
    %{
      title: gettext("photography.gallery.japan_title"),
      description:
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
      photo_url: "/images/photography/japan.webp"
    },
    %{
      title: gettext("photography.gallery.taiwan_title"),
      description:
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
      photo_url: "/images/photography/taiwan.webp"
    }
  ]

  # Récupère les photos d'un album depuis la base de données
  defp get_album_photos(album_slug) when is_binary(album_slug) do
    case Photography.get_album_by_slug(album_slug) do
      {:ok, album} ->
        build_photos_data(album)

      {:error, :not_found} ->
        @default_data
    end
  end

  defp get_album_photos(_), do: @default_data

  # Construit la liste des données de photos depuis un album
  defp build_photos_data(album) do
    photos = Photography.list_photos_by_album(album.id)

    if Enum.empty?(photos) do
      @default_data
    else
      Enum.map(photos, fn photo ->
        %{
          title: photo.title || album.title,
          description: photo.description || album.description || "",
          photo_url: photo.file_path,
          # Add alt text for SEO
          alt_text: generate_alt_text(photo, album),
          # Keep references for potential future use
          photo: photo,
          album: album
        }
      end)
    end
  end

  @impl true
  def mount(params, session, socket) do
    chapter = Map.get(params, "chapter", nil)
    language = Map.get(params, "hl", session["locale"] || "fr")
    Gettext.put_locale(PortfolioWeb.Gettext, language)
    data = get_album_photos(chapter)

    # Generate Schema.org JSON-LD for SEO
    schema_json = generate_gallery_schema(chapter, data)
    breadcrumb_json = generate_breadcrumb_schema(chapter)

    {
      :ok,
      socket
      |> assign(chapter: chapter)
      |> assign(language: language)
      |> assign(data: data)
      |> assign(pictures: Enum.count(data))
      |> assign(project_id: 0)
      |> assign(schema_json: schema_json)
      |> assign(breadcrumb_json: breadcrumb_json)
    }
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("show_project", %{"project" => id}, socket) do
    project = get_data(socket.assigns.data, id)

    {
      :noreply,
      socket
      |> assign(
        :page_title,
        gettext("photography.page_title") <> " - #{socket.assigns.chapter} - #{project.title}"
      )
      |> assign(project: project)
      |> assign(project_id: id)
    }
  end

  defp apply_action(socket, :index, %{"project" => id}) do
    project = get_data(socket.assigns.data, id)
    album_description = extract_album_description(socket.assigns.data)

    socket
    |> assign(
      :page_title,
      gettext("photography.brand") <> " - #{socket.assigns.chapter} - #{project.title}"
    )
    |> assign(:meta_description, album_description)
    |> assign(project: project)
    |> assign(project_id: id)
  end

  defp apply_action(socket, :index, _params) do
    id = "0"
    album_description = extract_album_description(socket.assigns.data)

    socket
    |> assign(:page_title, gettext("photography.page_title") <> " - #{socket.assigns.chapter}")
    |> assign(:meta_description, album_description)
    |> assign(project: get_data(socket.assigns.data, id))
    |> assign(project_id: id)
  end

  defp get_data(data, id), do: Enum.at(data, String.to_integer(id))

  defp generate_gallery_schema(nil, _data), do: nil

  defp generate_gallery_schema(_chapter, data) when data == @default_data, do: nil

  defp generate_gallery_schema(chapter, data) do
    # Extract album and photos from the data
    if Enum.empty?(data) or not Map.has_key?(List.first(data), :album) do
      nil
    else
      first_item = List.first(data)
      album = first_item.album
      photos = Enum.map(data, & &1.photo)
      url = "https://photo.thibaultsan.com/#{chapter}"

      image_gallery_schema(album, photos, url)
    end
  end

  defp generate_breadcrumb_schema(nil), do: nil

  defp generate_breadcrumb_schema(chapter) do
    breadcrumbs = [
      %{name: "Home", url: "https://photo.thibaultsan.com"},
      %{name: "Timeline", url: "https://photo.thibaultsan.com/timeline"},
      %{name: String.capitalize(chapter), url: "https://photo.thibaultsan.com/#{chapter}"}
    ]

    breadcrumb_schema(breadcrumbs)
  end

  defp extract_album_description(data) when data == @default_data do
    gettext("layouts.photography.description")
  end

  defp extract_album_description(data) do
    if Enum.empty?(data) or not Map.has_key?(List.first(data), :album) do
      gettext("layouts.photography.description")
    else
      first_item = List.first(data)
      album = first_item.album
      album.description || album.title || gettext("layouts.photography.description")
    end
  end
end
