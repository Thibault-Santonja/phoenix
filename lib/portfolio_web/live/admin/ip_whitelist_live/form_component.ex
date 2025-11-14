defmodule PortfolioWeb.Admin.IPWhitelistLive.FormComponent do
  @moduledoc """
  Form component for adding/editing a whitelisted IP.
  """

  use PortfolioWeb, :live_component

  alias Portfolio.Auth.{IPWhitelist, IPWhitelistService}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.simple_form
        for={@form}
        id="ip-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:ip_address]}
          type="text"
          label="IP Address"
          placeholder="192.168.1.100 or 2001:db8::1"
          disabled={@action == :edit}
        />
        <.input
          field={@form[:description]}
          type="text"
          label="Description (optional)"
          placeholder="Main office, VPN, etc."
        />

        <:actions>
          <.button phx-disable-with="Saving...">Save</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{ip_whitelist: ip_whitelist} = assigns, socket) do
    changeset = IPWhitelist.changeset(ip_whitelist, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"ip_whitelist" => ip_params}, socket) do
    changeset =
      socket.assigns.ip_whitelist
      |> IPWhitelist.changeset(ip_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"ip_whitelist" => ip_params}, socket) do
    save_ip_whitelist(socket, socket.assigns.action, ip_params)
  end

  defp save_ip_whitelist(socket, :new, ip_params) do
    case IPWhitelistService.add_to_whitelist(ip_params, socket.assigns.current_user.id) do
      {:ok, _ip_whitelist} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("admin.ip_whitelist.add_success"))
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_ip_whitelist(socket, :edit, ip_params) do
    case IPWhitelistService.update_whitelist_entry(socket.assigns.ip_whitelist, ip_params) do
      {:ok, _ip_whitelist} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("admin.ip_whitelist.update_success"))
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
