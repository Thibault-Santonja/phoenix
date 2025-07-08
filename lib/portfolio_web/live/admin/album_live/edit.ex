defmodule PortfolioWeb.Admin.AlbumLive.Edit do
  @moduledoc """
  LiveView pour l'édition d'un album existant.
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Photography
  alias Portfolio.Photography.Album

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    album = Photography.get_album!(id)
    changeset = Album.changeset(album, %{})

    {:ok,
     socket
     |> assign(:page_title, "Éditer l'album")
     |> assign(:album, album)
     |> assign(:form, to_form(changeset))
     |> assign(:album_types, album_type_options())}
  end

  @impl true
  def handle_event("validate", %{"album" => album_params}, socket) do
    changeset =
      socket.assigns.album
      |> Album.changeset(album_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"album" => album_params}, socket) do
    case Photography.update_album(socket.assigns.album, album_params) do
      {:ok, _album} ->
        {:noreply,
         socket
         |> put_flash(:info, "Album mis à jour avec succès")
         |> push_navigate(to: ~p"/admin/albums")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp album_type_options do
    Photography.list_album_types()
    |> Enum.map(fn type ->
      {format_type(type), type}
    end)
  end

  defp format_type(:couples), do: "Couples"
  defp format_type(:wedding), do: "Mariage"
  defp format_type(:motherhood), do: "Maternité"
  defp format_type(:events), do: "Événements"
  defp format_type(:landscape), do: "Paysage"
  defp format_type(:street), do: "Street"
  defp format_type(:music), do: "Musique"
  defp format_type(:reenactment), do: "Reconstitution"
  defp format_type(:amvcc), do: "AMVCC"
  defp format_type(:china), do: "Chine"
  defp format_type(:japan), do: "Japon"
  defp format_type(:taiwan), do: "Taïwan"
  defp format_type(type), do: to_string(type)
end
