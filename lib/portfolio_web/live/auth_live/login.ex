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
     |> assign(:page_title, gettext("auth.login.page_title"))
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
         |> put_flash(:info, gettext("auth.login.link_sent", email: email))}

      {:error, {:rate_limit_exceeded, retry_after}} ->
        {:noreply,
         socket
         |> assign(:retry_after, retry_after)
         |> put_flash(
           :error,
           gettext("auth.login.rate_limit_exceeded", time: format_retry_after(retry_after))
         )}

      {:error, :user_not_found} ->
        # Anti-énumération: retourner le même message que le succès
        # pour ne pas révéler si l'email existe ou non
        {:noreply,
         socket
         |> assign(:link_sent, true)
         |> assign(:retry_after, nil)
         |> put_flash(:info, gettext("auth.login.link_sent", email: email))}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:retry_after, nil)
         |> put_flash(:error, gettext("auth.login.send_error"))}
    end
  end

  defp format_retry_after(seconds) when seconds < 60,
    do: gettext("auth.login.seconds", count: seconds)

  defp format_retry_after(seconds),
    do: gettext("auth.login.minutes", count: div(seconds, 60))

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
      |> validate_required([:email])
      |> validate_format(:email, @email_regex)
    end
  end

  # Changeset for email validation
  defp email_changeset(params) do
    EmailForm.changeset(%EmailForm{}, params)
  end
end
