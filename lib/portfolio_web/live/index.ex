defmodule PortfolioWeb.Live.Index do
  @moduledoc """
  The main live view for the landing page of the portfolio.

  This module handles the initial entry point into the digital workshop.
  """
  use PortfolioWeb, :live_view
  import PortfolioWeb.SEO.SchemaHelpers

  @impl true
  def mount(_, session, socket) do
    # Récupérer la locale de la session, avec fallback sur "fr" si nil
    locale = session["locale"] || "fr"
    Gettext.put_locale(PortfolioWeb.Gettext, locale)

    # Add Schema.org structured data for homepage
    schema_json = website_schema()

    {:ok, assign(socket, schema_json: schema_json)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {
      :noreply,
      push_event(socket, "change_locale", %{"locale" => locale})
    }
  end

  defp apply_action(socket, :index, _params) do
    socket
  end
end
