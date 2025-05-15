defmodule PortfolioWeb.AmvccLive.Shoes do
  use PortfolioWeb, :live_view

  @impl true
  def mount(_, session, socket) do
    Gettext.put_locale(PortfolioWeb.Gettext, session["locale"])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Shoes XIVc in western Europe"))
  end
end
