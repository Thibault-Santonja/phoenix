defmodule PortfolioWeb.PhotographyLive.Gallery do
  use PortfolioWeb, :live_view
  import PortfolioWeb.Components.DarkModeButton

  @data [
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

  @impl true
  def mount(params, session, socket) do
    chapter = Map.get(params, "chapter", nil)
    language = Map.get(params, "hl", session["locale"])
    Gettext.put_locale(PortfolioWeb.Gettext, language)

    {
      :ok,
      socket
      |> assign(chapter: chapter)
      |> assign(language: language)
      |> assign(data: @data)
    }
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("show_project", %{"project" => id}, socket) do
    project = get_data(id)

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
    project = get_data(id)

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
    |> assign(project: get_data(id))
    |> assign(project_id: id)
  end

  defp get_data(id), do: Enum.at(@data, String.to_integer(id))
end
