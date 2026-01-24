defmodule PortfolioWeb.AmvccLive.Index do
  @moduledoc """
  LiveView for the AMVCC (Association Médiévale de la Ville et du Château de Coucy) section.

  Displays information about the medieval association and its activities.
  """
  use PortfolioWeb, :live_view

  @impl true
  def mount(_, session, socket) do
    locale = session["locale"] || "fr"
    _ = Gettext.put_locale(PortfolioWeb.Gettext, locale)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "La Seigneurie de Coucy")
  end
end
