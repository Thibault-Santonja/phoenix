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

  def format_chapter_title("amvcc"), do: "AMVCC"
  def format_chapter_title("china"), do: gettext("album.type.china")
  def format_chapter_title("couples"), do: gettext("album.type.couples")
  def format_chapter_title("events"), do: gettext("album.type.events")
  def format_chapter_title("japan"), do: gettext("album.type.japan")
  def format_chapter_title("landscape"), do: gettext("album.type.landscape")
  def format_chapter_title("motherhood"), do: gettext("photography.motherhood_families")
  def format_chapter_title("music"), do: gettext("photography.concerts_music")
  def format_chapter_title("reenactment"), do: gettext("album.type.reenactment")
  def format_chapter_title("street"), do: gettext("photography.street_photography")
  def format_chapter_title("taiwan"), do: gettext("album.type.taiwan")
  def format_chapter_title("wedding"), do: gettext("album.type.wedding")
  def format_chapter_title(_), do: gettext("photography.gallery")
end
