defmodule PortfolioWeb.AuthLive.Login do
  @moduledoc """
  LiveView pour la page de login via magic link.
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Auth

  @impl true
  def mount(_params, _session, socket) do
    changeset = email_changeset(%{})

    {:ok,
     socket
     |> assign(:page_title, "Connexion Admin")
     |> assign(:form, to_form(changeset))
     |> assign(:link_sent, false)}
  end

  @impl true
  def handle_event("validate", %{"email_form" => params}, socket) do
    changeset =
      params
      |> email_changeset()
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("request_link", %{"email_form" => %{"email" => email}}, socket) do
    changeset = email_changeset(%{"email" => email})

    if changeset.valid? do
      do_request_link(email, socket)
    else
      {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp do_request_link(email, socket) do
    case Auth.request_magic_link(email) do
      {:ok, _magic_link} ->
        {:noreply,
         socket
         |> assign(:link_sent, true)
         |> put_flash(:info, "Un lien de connexion a été envoyé à #{email}")}

      {:error, :rate_limit_exceeded} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Trop de tentatives. Veuillez patienter avant de réessayer."
         )}

      {:error, :user_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Accès non autorisé. Cet email n'est pas enregistré.")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Impossible d'envoyer le lien. Vérifiez votre adresse email.")}
    end
  end

  # Schema for email validation using embedded schema
  defmodule EmailForm do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :email, :string
    end

    def changeset(form, attrs) do
      form
      |> cast(attrs, [:email])
      |> validate_required([:email], message: "L'email est requis")
      |> validate_format(:email, ~r/@/, message: "L'email doit être valide")
    end
  end

  # Changeset for email validation
  defp email_changeset(params) do
    EmailForm.changeset(%EmailForm{}, params)
  end
end
