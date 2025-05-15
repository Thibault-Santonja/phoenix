defmodule PortfolioWeb.AmvccLive.Shoes do
  use PortfolioWeb, :live_view

  @impl true
  def mount(_, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Chaussures XIVe"))
  end
end
