defmodule PortfolioWeb.AmvccLive.Blog.Clothes do
  @moduledoc """
  LiveView for a themed article page dedicated to material culture in 14th-century Western Europe.

  This specific page focuses on clothing ("Clothing XIVc in western Europe") and explores textiles, tailoring,
  and fashion trends of the time through visual and archaeological documentation, with a special focus on
  reconstructed daily life in northern France.

  The page is part of the Seigneurie de Coucy blog.
  """

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
    |> assign(:page_title, gettext("Clothes XIVc in western Europe"))
  end
end
