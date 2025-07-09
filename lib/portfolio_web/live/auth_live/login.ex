defmodule PortfolioWeb.AuthLive.Login do
  @moduledoc """
  LiveView pour la page de login via magic link.
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Auth

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Connexion Admin")
     |> assign(:email, "")
     |> assign(:link_sent, false)}
  end

  @impl true
  def handle_event("request_link", %{"email" => email}, socket) do
    case Auth.request_magic_link(email) do
      {:ok, _magic_link} ->
        {:noreply,
         socket
         |> assign(:link_sent, true)
         |> assign(:email, email)
         |> put_flash(:info, "Un lien de connexion a été envoyé à #{email}")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Impossible d'envoyer le lien. Vérifiez votre adresse email.")}
    end
  end
end
