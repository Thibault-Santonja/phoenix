defmodule PortfolioWeb.Admin.AlbumLive.FormComponent do
  @moduledoc """
  Composant LiveView réutilisable pour le formulaire d'album.

  Gère la création et la modification d'albums.
  Élimine la duplication entre New et Edit LiveViews.
  """

  use PortfolioWeb, :live_component

  alias Portfolio.Photography
  alias Portfolio.Photography.Album

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          <%= if @action == :new do %>
            Créez un nouvel album photo
          <% else %>
            Modifiez les informations de l'album
          <% end %>
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="album-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Titre" required />

        <.input
          field={@form[:type]}
          type="select"
          label="Type"
          options={@album_types}
          prompt="Sélectionner un type"
          required
        />

        <.input field={@form[:description]} type="textarea" label="Description" rows="4" />

        <.input field={@form[:location]} type="text" label="Lieu" />

        <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
          <.input
            field={@form[:date_prise_vue]}
            type="date"
            label="Date de début de prise de vue"
            required
          />

          <.input field={@form[:date_fin_prise_vue]} type="date" label="Date de fin (optionnel)" />
        </div>

        <.input
          field={@form[:reference_link]}
          type="url"
          label="Lien de référence"
          placeholder="https://..."
        />

        <.input field={@form[:published]} type="checkbox" label="Publié" />

        <:actions>
          <.button phx-disable-with="Enregistrement...">
            {if @action == :new, do: "Créer l'album", else: "Enregistrer les modifications"}
          </.button>
          <.link navigate={~p"/admin/albums"} class="text-sm text-gray-600 hover:text-gray-900">
            Annuler
          </.link>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{album: album} = assigns, socket) do
    changeset = Album.changeset(album, %{})

    {:ok,
     socket
     |> assign(assigns)
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
    save_album(socket, socket.assigns.action, album_params)
  end

  defp save_album(socket, :new, album_params) do
    case Photography.create_album(album_params) do
      {:ok, album} ->
        notify_parent({:saved, album})

        {:noreply,
         socket
         |> put_flash(:info, "Album créé avec succès")
         |> push_navigate(to: ~p"/admin/albums/#{album.id}/edit")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_album(socket, :edit, album_params) do
    case Photography.update_album(socket.assigns.album, album_params) do
      {:ok, album} ->
        notify_parent({:saved, album})

        {:noreply,
         socket
         |> put_flash(:info, "Album mis à jour avec succès")
         |> push_navigate(to: ~p"/admin/albums")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

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
