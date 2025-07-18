defmodule PortfolioWeb.Admin.AlbumLive.Edit do
  @moduledoc """
  LiveView pour l'édition d'un album existant.
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Photography
  alias Portfolio.Photography.Album

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    album = Photography.get_album!(id, preload: [:photos])
    changeset = Album.changeset(album, %{})

    {:ok,
     socket
     |> assign(:page_title, "Éditer l'album")
     |> assign(:album, album)
     |> assign(:form, to_form(changeset))
     |> assign(:album_types, album_type_options())
     |> assign(:uploaded_files, [])
     |> assign(:editing_photo, nil)
     |> assign(:photo_form, nil)
     |> assign(:reordering_mode, false)
     |> assign(:temp_photo_order, [])
     |> allow_upload(:photos,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 20,
       max_file_size: 10_000_000,
       auto_upload: true
     )}
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

  @impl true
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photos, ref)}
  end

  @impl true
  def handle_event("upload", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        # Pour l'instant, on stocke juste le nom de fichier
        # On implémentera le storage réel dans Issue #12-14
        dest = Path.join(["priv", "static", "uploads", "#{entry.uuid}.#{ext(entry)}"])
        File.mkdir_p!(Path.dirname(dest))
        File.cp!(path, dest)

        file_path = "/uploads/#{entry.uuid}.#{ext(entry)}"
        {:ok, {file_path, entry.client_name}}
      end)

    # Créer les photos dans la DB
    album = socket.assigns.album

    Enum.each(uploaded_files, fn {file_path, original_filename} ->
      Photography.create_photo(%{
        album_id: album.id,
        file_path: file_path,
        original_filename: original_filename,
        display_order: length(album.photos)
      })
    end)

    # Recharger l'album avec les nouvelles photos
    updated_album = Photography.get_album!(album.id, preload: [:photos])

    {:noreply,
     socket
     |> assign(:album, updated_album)
     |> assign(:uploaded_files, uploaded_files)
     |> put_flash(:info, "#{length(uploaded_files)} photo(s) ajoutée(s)")}
  end

  @impl true
  def handle_event("delete_photo", %{"id" => id}, socket) do
    photo = Photography.get_photo!(id)
    {:ok, _} = Photography.delete_photo(photo)

    updated_album = Photography.get_album!(socket.assigns.album.id, preload: [:photos])

    {:noreply,
     socket
     |> assign(:album, updated_album)
     |> put_flash(:info, "Photo supprimée")}
  end

  @impl true
  def handle_event("edit_photo", %{"id" => id}, socket) do
    photo = Photography.get_photo!(id)
    changeset = Portfolio.Photography.Photo.changeset(photo, %{})

    {:noreply,
     socket
     |> assign(:editing_photo, photo)
     |> assign(:photo_form, to_form(changeset))}
  end

  @impl true
  def handle_event("close_photo_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_photo, nil)
     |> assign(:photo_form, nil)}
  end

  @impl true
  def handle_event("validate_photo", %{"photo" => photo_params}, socket) do
    changeset =
      socket.assigns.editing_photo
      |> Portfolio.Photography.Photo.changeset(photo_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :photo_form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_photo", %{"photo" => photo_params}, socket) do
    case Photography.update_photo(socket.assigns.editing_photo, photo_params) do
      {:ok, _photo} ->
        updated_album = Photography.get_album!(socket.assigns.album.id, preload: [:photos])

        {:noreply,
         socket
         |> assign(:album, updated_album)
         |> assign(:editing_photo, nil)
         |> assign(:photo_form, nil)
         |> put_flash(:info, "Photo mise à jour avec succès")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :photo_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("start_reordering", _params, socket) do
    # Sauvegarder l'ordre actuel des photos (IDs)
    photo_ids = Enum.map(socket.assigns.album.photos, & &1.id)

    {:noreply,
     socket
     |> assign(:reordering_mode, true)
     |> assign(:temp_photo_order, photo_ids)}
  end

  @impl true
  def handle_event("cancel_reordering", _params, socket) do
    {:noreply,
     socket
     |> assign(:reordering_mode, false)
     |> assign(:temp_photo_order, [])}
  end

  @impl true
  def handle_event("reorder_photos", %{"photo_ids" => photo_ids}, socket) do
    # Mettre à jour l'ordre temporaire
    {:noreply, assign(socket, :temp_photo_order, photo_ids)}
  end

  @impl true
  def handle_event("save_photo_order", _params, socket) do
    # Mettre à jour display_order de chaque photo
    socket.assigns.temp_photo_order
    |> Enum.with_index()
    |> Enum.each(fn {photo_id, index} ->
      photo = Photography.get_photo!(photo_id)
      Photography.update_photo(photo, %{display_order: index})
    end)

    # Recharger l'album avec le nouvel ordre
    updated_album = Photography.get_album!(socket.assigns.album.id, preload: [:photos])

    {:noreply,
     socket
     |> assign(:album, updated_album)
     |> assign(:reordering_mode, false)
     |> assign(:temp_photo_order, [])
     |> put_flash(:info, "Ordre des photos enregistré")}
  end

  defp ext(entry) do
    [ext | _] = MIME.extensions(entry.client_type)
    ext
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
