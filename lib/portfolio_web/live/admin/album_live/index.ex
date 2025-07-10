defmodule PortfolioWeb.Admin.AlbumLive.Index do
  @moduledoc """
  LiveView pour la liste des albums dans l'interface admin.

  Permet de :
  - Visualiser tous les albums avec leur statut
  - Créer un nouvel album
  - Éditer un album existant
  - Supprimer un album
  - Basculer le statut published d'un album
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Photography

  on_mount PortfolioWeb.LiveAuth

  @impl true
  def mount(_params, _session, socket) do
    albums = Photography.list_albums(preload: [:photos])

    {:ok,
     socket
     |> assign(:albums, albums)
     |> assign(:page_title, "Albums")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Albums")
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    album = Photography.get_album!(id)

    case Photography.delete_album(album) do
      {:ok, _album} ->
        albums = Photography.list_albums(preload: [:photos])

        {:noreply,
         socket
         |> put_flash(:info, "Album supprimé avec succès")
         |> assign(:albums, albums)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Impossible de supprimer l'album")}
    end
  end

  @impl true
  def handle_event("toggle_publish", %{"id" => id}, socket) do
    album = Photography.get_album!(id)

    case Photography.update_album(album, %{published: !album.published}) do
      {:ok, _album} ->
        albums = Photography.list_albums(preload: [:photos])

        {:noreply,
         socket
         |> put_flash(:info, "Statut de publication mis à jour")
         |> assign(:albums, albums)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Impossible de mettre à jour le statut")}
    end
  end

  # Fonction helper pour formater les types d'albums
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

  # Fonction helper pour le badge de type
  defp type_badge_class(:wedding), do: "bg-pink-100 text-pink-800"
  defp type_badge_class(:couples), do: "bg-purple-100 text-purple-800"
  defp type_badge_class(:motherhood), do: "bg-blue-100 text-blue-800"
  defp type_badge_class(:events), do: "bg-green-100 text-green-800"
  defp type_badge_class(:landscape), do: "bg-emerald-100 text-emerald-800"
  defp type_badge_class(:street), do: "bg-gray-100 text-gray-800"
  defp type_badge_class(:music), do: "bg-indigo-100 text-indigo-800"
  defp type_badge_class(:reenactment), do: "bg-amber-100 text-amber-800"
  defp type_badge_class(:amvcc), do: "bg-red-100 text-red-800"
  defp type_badge_class(:china), do: "bg-yellow-100 text-yellow-800"
  defp type_badge_class(:japan), do: "bg-rose-100 text-rose-800"
  defp type_badge_class(:taiwan), do: "bg-cyan-100 text-cyan-800"
  defp type_badge_class(_), do: "bg-gray-100 text-gray-800"
end
