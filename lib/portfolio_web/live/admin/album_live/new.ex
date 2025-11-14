defmodule PortfolioWeb.Admin.AlbumLive.New do
  @moduledoc """
  LiveView pour la création d'un nouvel album.

  Utilise FormComponent pour le formulaire partagé.
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Photography.Album
  alias PortfolioWeb.Admin.AlbumLive.FormComponent

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("New Album"))
     |> assign(:album, %Album{})}
  end

  @impl true
  def handle_info({FormComponent, {:saved, _album}}, socket) do
    # Le FormComponent gère déjà la navigation après la sauvegarde
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="flex items-start justify-between mb-4">
        <.back_to_dashboard />
        <.admin_logout_button current_user={@current_user} />
      </div>

      <div class="max-w-2xl mx-auto">
        <.live_component
          module={FormComponent}
          id="new-album-form"
          title={gettext("New Album")}
          action={:new}
          album={@album}
        />
      </div>
    </div>
    """
  end
end
