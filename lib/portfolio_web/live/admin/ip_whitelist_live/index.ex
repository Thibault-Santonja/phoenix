defmodule PortfolioWeb.Admin.IPWhitelistLive.Index do
  @moduledoc """
  LiveView for managing the IP address whitelist.

  Allows administrators to add, modify, and delete IP addresses
  that will not be subject to rate limiting.
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Auth.{IPWhitelist, IPWhitelistService}

  on_mount PortfolioWeb.LiveAuth

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_whitelist(socket)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> load_whitelist()
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("admin.ip_whitelist.title"))
    |> assign(:ip_whitelist, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, gettext("admin.ip_whitelist.new"))
    |> assign(:ip_whitelist, %IPWhitelist{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, gettext("admin.ip_whitelist.edit"))
    |> assign(:ip_whitelist, IPWhitelistService.get_whitelist_entry(id))
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case IPWhitelistService.remove_from_whitelist(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("admin.ip_whitelist.delete_success"))
         |> load_whitelist()}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("admin.ip_whitelist.delete_error"))}
    end
  end

  defp load_whitelist(socket) do
    entries = IPWhitelistService.list_whitelist()
    assign(socket, :entries, entries)
  end
end
