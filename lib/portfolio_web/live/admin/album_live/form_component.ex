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
            {gettext("admin.albums.form.subtitle_new")}
          <% else %>
            {gettext("admin.albums.form.subtitle_edit")}
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
        <.input field={@form[:title]} type="text" label={gettext("admin.albums.form.title")} required />

        <.input
          field={@form[:type]}
          type="select"
          label={gettext("admin.albums.form.type")}
          options={@album_types}
          prompt={gettext("admin.albums.form.select_type")}
          required
        />

        <.input
          field={@form[:description]}
          type="textarea"
          label={gettext("admin.albums.form.description")}
          rows="4"
        />

        <.input field={@form[:location]} type="text" label={gettext("admin.albums.form.location")} />

        <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
          <.input
            field={@form[:date_prise_vue]}
            type="date"
            label={gettext("admin.albums.form.start_date")}
            required
          />

          <.input
            field={@form[:date_fin_prise_vue]}
            type="date"
            label={gettext("admin.albums.form.end_date")}
          />
        </div>

        <.input
          field={@form[:reference_link]}
          type="url"
          label={gettext("admin.albums.form.reference_link")}
          placeholder="https://..."
        />

        <.input
          field={@form[:published]}
          type="checkbox"
          label={gettext("admin.albums.form.published")}
        />

        <:actions>
          <.button phx-disable-with={gettext("admin.albums.form.saving")}>
            {if @action == :new,
              do: gettext("admin.albums.form.create"),
              else: gettext("admin.albums.form.save")}
          </.button>
          <.link navigate={~p"/admin/albums"} class="text-sm text-gray-600 hover:text-gray-900">
            {gettext("admin.albums.form.cancel")}
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
         |> put_flash(:info, gettext("admin.albums.form.create_success"))
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
         |> put_flash(:info, gettext("admin.albums.form.update_success"))
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

  defp format_type(:couples), do: gettext("album.type.couples")
  defp format_type(:wedding), do: gettext("album.type.wedding")
  defp format_type(:motherhood), do: gettext("album.type.motherhood")
  defp format_type(:events), do: gettext("album.type.events")
  defp format_type(:landscape), do: gettext("album.type.landscape")
  defp format_type(:street), do: gettext("album.type.street")
  defp format_type(:music), do: gettext("album.type.music")
  defp format_type(:reenactment), do: gettext("album.type.reenactment")
  defp format_type(:amvcc), do: "AMVCC"
  defp format_type(:china), do: gettext("album.type.china")
  defp format_type(:japan), do: gettext("album.type.japan")
  defp format_type(:taiwan), do: gettext("album.type.taiwan")
  defp format_type(type), do: to_string(type)
end
