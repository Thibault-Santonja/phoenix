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
  @supported_album ["20250614_MALN"]

  defp get_folder_pictures(chapter) when chapter in @supported_album do
    "./priv/static/images/photography/#{chapter}/*.webp"
    |> Path.wildcard()
    |> Stream.map(&String.split(&1, "priv/static", trim: true))
    |> Stream.map(fn url ->
      %{
        title: "Minuit avant la nuit 2025",
        description:
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
        photo_url: url
      }
    end)
    |> Enum.to_list()
  end

  defp get_folder_pictures(_), do: @default_data

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
