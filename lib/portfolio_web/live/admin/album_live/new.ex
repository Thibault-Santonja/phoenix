defmodule PortfolioWeb.Admin.AlbumLive.New do
  @moduledoc """
  LiveView pour la création d'un nouvel album.
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Photography
  alias Portfolio.Photography.Album

  @impl true
  def mount(_params, _session, socket) do
    changeset = Album.changeset(%Album{}, %{})

    {:ok,
     socket
     |> assign(:page_title, "Nouvel Album")
     |> assign(:album, %Album{})
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
    case Photography.create_album(album_params) do
      {:ok, _album} ->
        {:noreply,
         socket
         |> put_flash(:info, "Album créé avec succès")
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
