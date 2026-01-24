defmodule Portfolio.Mailer do
  @moduledoc """
  Application mailer using Swoosh.

  Handles sending emails for authentication, notifications, etc.

  ## Configuration

  Configure the mailer adapter in config:

      # Development - local testing
      config :portfolio, Portfolio.Mailer,
        adapter: Swoosh.Adapters.Local

      # Production - use SMTP, Mailgun, SendGrid, etc.
      config :portfolio, Portfolio.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: "smtp.gmail.com",
        username: System.get_env("SMTP_USERNAME"),
        password: System.get_env("SMTP_PASSWORD")

  ## Usage

      import Swoosh.Email

      new()
      |> to("user@example.com")
      |> from({"Portfolio", "noreply@portfolio.com"})
      |> subject("Welcome!")
      |> html_body("<h1>Welcome to Portfolio</h1>")
      |> Portfolio.Mailer.deliver()
  """

  use Swoosh.Mailer, otp_app: :portfolio
end
