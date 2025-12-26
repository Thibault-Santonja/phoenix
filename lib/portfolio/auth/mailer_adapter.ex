defmodule Portfolio.Auth.MailerAdapter do
  @moduledoc """
  Behaviour for email sending adapters.

  Defines the contract for sending authentication emails.
  Allows swapping implementations for different environments
  (SMTP, SendGrid, AWS SES, etc.) without changing business logic.

  ## Implementations

  - `Portfolio.Auth.Mailer` - Default Swoosh-based implementation

  ## Configuration

  Configure the adapter in your config:

      config :portfolio, :mailer_adapter, Portfolio.Auth.Mailer

  ## Usage

      adapter = Application.get_env(:portfolio, :mailer_adapter, Portfolio.Auth.Mailer)
      adapter.send_magic_link_email(user, magic_link)

  """

  alias Portfolio.Auth.{MagicLink, User}

  @doc """
  Sends an email containing the magic link to the user.

  ## Parameters

  - `user` - The user to send the email to
  - `magic_link` - The magic link containing the login token

  ## Returns

  - `{:ok, term()}` if the email was sent successfully
  - `{:error, term()}` in case of error

  """
  @callback send_magic_link_email(User.t(), MagicLink.t()) :: {:ok, term()} | {:error, term()}
end
