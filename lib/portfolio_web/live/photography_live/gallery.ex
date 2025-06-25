defmodule PortfolioWeb.PhotographyLive.Gallery do
  use PortfolioWeb, :live_view
  import PortfolioWeb.Components.ThemeButton

  @default_data [
    %{
      title: gettext("A title in China"),
      description:
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
      photo_url: "/images/photography/china.webp"
    },
    %{
      title: gettext("This title Japan"),
      description:
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
      photo_url: "/images/photography/japan.webp"
    },
    %{
      title: gettext("A Taiwan title"),
      description:
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
      photo_url: "/images/photography/taiwan.webp"
    }
  ]
  @supported_album ["20250614_MALN", "20250621_Bours"]

  defp get_folder_pictures(chapter) when chapter in @supported_album do
    :code.priv_dir(:portfolio)
    |> Path.join("./static/images/photography/#{chapter}/*.webp")
    |> Path.wildcard()
    |> Stream.map(&get_url/1)
    |> Stream.reject(&skip_file_in_prod?/1)
    |> Stream.map(&build_photo_data/1)
    |> Enum.to_list()
  end

  defp get_folder_pictures(_), do: @default_data

  defp build_photo_data(url) do
    %{
      title: "No title",
      description: "No description",
      photo_url: "/" <> url
    }
  end

  defp skip_file_in_prod?(url) do
    if System.get_env("MIX_ENV") == :prod do
      not Regex.match?(~r/-[a-f0-9]{8,}\.webp$/, url)
    else
      false
    end
  end

  defp get_url(path) do
    [_priv_path, url] = String.split(path, "/static/", trim: true)
    url
  end

  @impl true
  def mount(params, session, socket) do
    chapter = Map.get(params, "chapter", nil)
    language = Map.get(params, "hl", session["locale"])
    Gettext.put_locale(PortfolioWeb.Gettext, language)
    data = get_folder_pictures(chapter)

    {
      :ok,
      socket
      |> assign(chapter: chapter)
      |> assign(language: language)
      |> assign(data: data)
      |> assign(pictures: Enum.count(data))
      |> assign(project_id: 1)
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
        gettext("Thibault San Photography") <> " - #{socket.assigns.chapter} - #{project.title}"
      )
      |> assign(project: project)
      |> assign(project_id: id)
    }
  end

  defp apply_action(socket, :index, %{"project" => id}) do
    project = get_data(socket.assigns.data, id)

    socket
    |> assign(
      :page_title,
      gettext("Thibault San Photography") <> " - #{socket.assigns.chapter} - #{project.title}"
    )
    |> assign(project: project)
    |> assign(project_id: id)
  end

  defp apply_action(socket, :index, _params) do
    id = "0"

    socket
    |> assign(:page_title, gettext("Thibault San Photography") <> " - #{socket.assigns.chapter}")
    |> assign(project: get_data(socket.assigns.data, id))
    |> assign(project_id: id)
  end

  defp get_data(data, id), do: Enum.at(data, String.to_integer(id))
end
