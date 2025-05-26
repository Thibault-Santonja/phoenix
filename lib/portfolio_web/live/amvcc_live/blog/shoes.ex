defmodule PortfolioWeb.AmvccLive.Blog.Shoes do
  @moduledoc """
  LiveView for a themed article page dedicated to material culture in 14th-century Western Europe.

  This specific page focuses on footwear ("Shoes XIVc in western Europe") and presents historical insights, iconography, and archaeological sources
  to illustrate the variety and function of shoes worn during the mid-14th century, particularly in regions like France, England, and the Low Countries.

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
    |> assign(:page_title, gettext("Shoes XIVc in western Europe"))
  end
end
