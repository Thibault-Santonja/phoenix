defmodule PortfolioWeb.PhotographyLive.Timeline do
  use PortfolioWeb, :live_view

  @data %{
    2023 => [
      %{
        date: "2023-03-27",
        title: "This is a title",
        description:
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
        photography: "/images/photography/japan.webp",
        url: "/?section=japan"
      }
    ],
    2024 => [
      %{
        date: "2024-05-18",
        title: "This is a title",
        description:
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
        photography: "/images/photography/japan.webp",
        url: "/?section=japan"
      },
      %{
        date: "2024-06-10",
        title: "This is a title",
        description:
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
        photography: "/images/photography/japan.webp",
        url: "/?section=japan"
      },
      %{
        date: "2024-07-29",
        title: "This is a title",
        description:
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
        photography: "/images/photography/japan.webp",
        url: "/?section=japan"
      },
      %{
        date: "2024-10-07",
        title: "This is a title",
        description:
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
        photography: "/images/photography/japan.webp",
        url: "/?section=japan"
      }
    ],
    2025 => [
      %{
        date: "2025-07-29",
        title: "This is a title",
        description:
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
        photography: "/images/photography/japan.webp",
        url: "/?section=japan"
      },
      %{
        date: "2025-10-07",
        title: "This is a title",
        description:
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
        photography: "/images/photography/japan.webp",
        url: "/?section=japan"
      }
    ]
  }

  @impl true
  def mount(_, session, socket) do
    Gettext.put_locale(PortfolioWeb.Gettext, session["locale"])

    {
      :ok,
      socket
      |> assign(data: @data)
      |> assign(years: @data |> Map.keys() |> Enum.sort(:desc))
    }
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {:noreply, push_event(socket, "change_locale", %{"locale" => locale})}
  end

  defp apply_action(socket, :index, %{"section" => section}) do
    socket
    |> assign(:section, section)
    |> assign(:page_title, build_title(section))
  end

  defp build_title(section) do
    gettext("Photographies gallery - ") <> String.capitalize(section)
  end
end
