defmodule PortfolioWeb.AmvccLive.Blog do
  @moduledoc """
  LiveView module for the blog landing page of the Seigneurie de Coucy section.

  This page serves as an entry point to historical articles, news, and updates
  related to the activities of the AMVCC (Association pour la Mise en Valeur
  du Château de Coucy). It supports locale-based rendering and dynamic updates
  through Phoenix LiveView.

  The view sets the page title and handles any future routing logic tied to
  blog-related content.
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
    |> assign(:page_title, "Blog")
  end
end
