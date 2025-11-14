defmodule PortfolioWeb.AuthLive.Login do
  @moduledoc """
  LiveView pour la page de login via magic link.
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Auth

  @impl true
  def mount(_params, _session, socket) do
    changeset = email_changeset(%{})

    # Get magic link TTL from config (in seconds)
    magic_link_ttl =
      Application.get_env(:portfolio, :auth, [])
      |> Keyword.get(:magic_link_ttl_minutes, 15)
      |> then(&(&1 * 60))

    {:ok,
     socket
     |> assign(:page_title, "Connexion Admin")
     |> assign(:form, to_form(changeset))
     |> assign(:link_sent, false)
     |> assign(:retry_after, nil)
     |> assign(:magic_link_ttl, magic_link_ttl)}
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
         |> assign(:retry_after, nil)
         |> put_flash(:info, "Un lien de connexion a été envoyé à #{email}")}

      {:error, {:rate_limit_exceeded, retry_after}} ->
        {:noreply,
         socket
         |> assign(:retry_after, retry_after)
         |> put_flash(
           :error,
           "Trop de tentatives. Veuillez patienter #{format_retry_after(retry_after)} avant de réessayer."
         )}

      {:error, :user_not_found} ->
        # Anti-énumération: retourner le même message que le succès
        # pour ne pas révéler si l'email existe ou non
        {:noreply,
         socket
         |> assign(:link_sent, true)
         |> assign(:retry_after, nil)
         |> put_flash(:info, "Un lien de connexion a été envoyé à #{email}")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:retry_after, nil)
         |> put_flash(:error, "Impossible d'envoyer le lien. Vérifiez votre adresse email.")}
    end
  end

  defp format_retry_after(seconds) when seconds < 60, do: "#{seconds} secondes"
  defp format_retry_after(seconds), do: "#{div(seconds, 60)} minutes"

  # Schema for email validation using embedded schema
  defmodule EmailForm do
    use Ecto.Schema
    import Ecto.Changeset

    @email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

    embedded_schema do
      field :email, :string
    end

    def changeset(form, attrs) do
      form
      |> cast(attrs, [:email])
      |> validate_required([:email], message: "L'email est requis")
      |> validate_format(:email, @email_regex, message: "L'email doit être valide")
    end
  end

  # Changeset for email validation
  defp email_changeset(params) do
    EmailForm.changeset(%EmailForm{}, params)
  end
end
