defmodule Portfolio.Auth.Mailer do
  @moduledoc """
  Module responsible for sending authentication emails via magic links.

  Implements the `Portfolio.Auth.MailerAdapter` behaviour for sending
  authentication emails using Swoosh.
  """

  @behaviour Portfolio.Auth.MailerAdapter

  import Swoosh.Email
  alias Portfolio.Auth.{MagicLink, User}

  @doc """
  Sends an email containing the magic link to the user.

  ## Parameters
    - user: The user to send the email to
    - magic_link: The magic link containing the login token

  ## Returns
    - `{:ok, _}` if the email was sent successfully
    - `{:error, reason}` in case of error
  """
  @impl Portfolio.Auth.MailerAdapter
  @spec send_magic_link_email(User.t(), MagicLink.t()) :: {:ok, term()} | {:error, term()}
  def send_magic_link_email(%User{} = user, %MagicLink{} = magic_link) do
    magic_link_url = generate_magic_link_url(magic_link)

    new()
    |> to({user.name || user.email, user.email})
    |> from({"Portfolio Admin", "noreply@portfolio.local"})
    |> subject("Votre lien de connexion")
    |> html_body("""
    <html>
      <body style="font-family: sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2 style="color: #333;">Connexion à votre espace admin</h2>

        <p>Bonjour #{user.name || user.email},</p>

        <p>Vous avez demandé un lien de connexion pour accéder à votre espace d'administration.</p>

        <p style="margin: 30px 0;">
          <a href="#{magic_link_url}"
             target="_blank"
             rel="noopener noreferrer"
             style="background-color: #4F46E5; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; display: inline-block;">
            Se connecter
          </a>
        </p>

        <p style="color: #666; font-size: 14px;">
          Ce lien est valide pendant <strong>15 minutes</strong> et ne peut être utilisé qu'une seule fois.
        </p>

        <p style="color: #666; font-size: 14px;">
          Si vous n'avez pas demandé ce lien, vous pouvez ignorer cet email en toute sécurité.
        </p>

        <hr style="border: none; border-top: 1px solid #eee; margin: 30px 0;" />

        <p style="color: #999; font-size: 12px;">
          Si le bouton ne fonctionne pas, copiez et collez ce lien dans votre navigateur :<br/>
          <a href="#{magic_link_url}" style="color: #4F46E5;">#{magic_link_url}</a>
        </p>
      </body>
    </html>
    """)
    |> text_body("""
    Connexion à votre espace admin

    Bonjour #{user.name || user.email},

    Vous avez demandé un lien de connexion pour accéder à votre espace d'administration.

    Cliquez sur le lien suivant pour vous connecter :
    #{magic_link_url}

    Ce lien est valide pendant 15 minutes et ne peut être utilisé qu'une seule fois.

    Si vous n'avez pas demandé ce lien, vous pouvez ignorer cet email en toute sécurité.
    """)
    |> Portfolio.Mailer.deliver()
  end

  # Génère l'URL complète du magic link
  # Utilise le short_code (6 caractères) au lieu du token complet pour plus de sécurité
  # Le token reste caché et sera soumis via POST
  defp generate_magic_link_url(magic_link) do
    # En développement, on utilise localhost:4000
    # En production, cela devrait être configuré via l'environnement
    base_url = Application.get_env(:portfolio, :base_url, "http://localhost:4000")
    "#{base_url}/auth/verify?code=#{magic_link.short_code}"
  end
end
