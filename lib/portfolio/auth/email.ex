defmodule Portfolio.Auth.Email do
  @moduledoc """
  Email templates for authentication.

  Provides functions to build emails for magic link authentication,
  password resets, and other auth-related notifications.
  """

  import Swoosh.Email

  @doc """
  Builds a magic link authentication email.

  ## Parameters

  - `email` - Recipient email address
  - `magic_link_url` - Full URL with magic link token

  ## Example

      iex> magic_link_email("user@example.com", "https://example.com/auth/verify?token=abc123")
      %Swoosh.Email{...}
  """
  @spec magic_link_email(String.t(), String.t()) :: Swoosh.Email.t()
  def magic_link_email(recipient_email, magic_link_url) do
    new()
    |> to(recipient_email)
    |> from({"Portfolio", from_email()})
    |> subject("Your login link")
    |> html_body(magic_link_html(magic_link_url))
    |> text_body(magic_link_text(magic_link_url))
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  @spec from_email() :: String.t()
  defp from_email do
    Application.get_env(:portfolio, :from_email, "noreply@portfolio.local")
  end

  @spec magic_link_html(String.t()) :: String.t()
  defp magic_link_html(magic_link_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
          line-height: 1.6;
          color: #333;
          max-width: 600px;
          margin: 0 auto;
          padding: 20px;
        }
        .button {
          display: inline-block;
          padding: 12px 24px;
          background-color: #4F46E5;
          color: white;
          text-decoration: none;
          border-radius: 6px;
          margin: 20px 0;
        }
        .footer {
          margin-top: 40px;
          padding-top: 20px;
          border-top: 1px solid #ddd;
          font-size: 12px;
          color: #666;
        }
      </style>
    </head>
    <body>
      <h1>Sign in to Portfolio</h1>
      <p>Click the button below to sign in to your account. This link will expire in 15 minutes.</p>

      <a href="#{magic_link_url}" class="button">Sign in to Portfolio</a>

      <p>Or copy and paste this link into your browser:</p>
      <p style="word-break: break-all; color: #666;">#{magic_link_url}</p>

      <div class="footer">
        <p>If you didn't request this email, you can safely ignore it.</p>
        <p>This is an automated email, please do not reply.</p>
      </div>
    </body>
    </html>
    """
  end

  @spec magic_link_text(String.t()) :: String.t()
  defp magic_link_text(magic_link_url) do
    """
    Sign in to Portfolio

    Click the link below to sign in to your account. This link will expire in 15 minutes.

    #{magic_link_url}

    If you didn't request this email, you can safely ignore it.

    This is an automated email, please do not reply.
    """
  end
end
