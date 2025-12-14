defmodule PortfolioWeb.PhotographyLive.Index do
  @moduledoc """
  LiveView for the photography portfolio index page.

  Displays photography chapters with modal descriptions.
  Modal content is extracted to ModalContent component for maintainability.
  """

  import PortfolioWeb.Components.PhotographyList
  import PortfolioWeb.Components.ThemeButton
  import PortfolioWeb.PhotographyLive.ModalContent
  use PortfolioWeb, :live_view

  alias PortfolioWeb.Helpers.AlbumTypeFormatter

  defdelegate format_chapter_title(chapter), to: AlbumTypeFormatter

  @impl true
  def mount(params, session, socket) do
    chapter = Map.get(params, "chapter", nil)
    language = Map.get(params, "hl", session["locale"] || "fr")
    _ = Gettext.put_locale(PortfolioWeb.Gettext, language)

    {
      :ok,
      socket
      |> assign(modal_chapter: chapter)
      |> assign(language: language)
    }
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("open_modal", %{"chapter" => chapter}, socket) do
    {
      :noreply,
      socket
      |> assign(:modal_chapter, chapter)
      |> push_patch(to: ~p"/?chapter=#{chapter}&hl=#{socket.assigns.language}")
    }
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {
      :noreply,
      socket
      |> assign(:modal_chapter, nil)
      |> push_patch(to: ~p"/?hl=#{socket.assigns.language}")
    }
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {
      :noreply,
      socket
      |> push_event("change_locale", %{"locale" => locale})
      |> assign(language: locale)
      |> push_patch(to: ~p"/?hl=#{locale}")
    }
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("photography.page_title"))
  end
end
