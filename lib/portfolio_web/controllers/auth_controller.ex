defmodule PortfolioWeb.AuthController do
  @moduledoc """
  Controller pour l'authentification via magic links.
  """

  use PortfolioWeb, :controller

  alias Portfolio.Auth

  # Rate limiting: 10 token verification attempts per 5 minutes per IP
  # Prevents brute force attacks on magic link tokens
  plug PortfolioWeb.Plugs.RateLimiterPlug,
       [action: :magic_link_verify, identifier: :ip]
       when action in [:verify_magic_link, :verify_magic_link_post, :magic_link_landing]

  @doc """
  Page intermédiaire qui reçoit le token via GET (depuis l'email) et
  prépare un formulaire POST pour la vérification sécurisée.

  Cette approche évite que le token apparaisse dans:
  - Les logs serveur (URL GET)
  - L'historique du navigateur
  - Les outils d'analytics
  - Les headers Referer
  """
  def magic_link_landing(conn, %{"token" => token}) do
    render(conn, :magic_link_landing, token: token)
  end

  @doc """
  Vérifie un magic link via POST (méthode sécurisée).

  Accepte le token dans le corps de la requête POST au lieu de l'URL,
  ce qui empêche sa fuite dans les logs et l'historique.
  """
  def verify_magic_link_post(conn, %{"token" => token}) do
    do_verify_magic_link(conn, token)
  end

  @doc """
  Vérifie un magic link via GET (méthode legacy, à éviter).

  DEPRECATED: Cette méthode est conservée pour la rétrocompatibilité
  avec les anciens liens email, mais devrait être remplacée par la méthode POST.

  Crée un token de session en base de données pour permettre:
  - La révocation de sessions spécifiques
  - L'expiration après 30 jours d'inactivité
  - Le tracking des sessions actives
  """
  def verify_magic_link(conn, %{"token" => token}) do
    conn
    |> put_flash(
      :info,
      "Vous utilisez un ancien lien de connexion. Les nouveaux liens sont plus sécurisés."
    )
    |> do_verify_magic_link(token)
  end

  # Logique partagée de vérification du magic link
  defp do_verify_magic_link(conn, token) do
    case Auth.verify_magic_link(token) do
      {:ok, user} ->
        # Créer un token de session en base de données
        case Auth.create_session(user) do
          {:ok, session} ->
            conn
            |> put_session(:session_token, session.token)
            # Assigner directement l'user pour éviter un fetch DB immédiat après redirect
            |> assign(:current_user, user)
            |> assign(:current_session, session)
            |> put_flash(:info, gettext("auth.login.success", email: user.email))
            |> redirect(to: ~p"/admin")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, gettext("auth.login.session_error"))
            |> redirect(to: ~p"/login")
        end

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, gettext("auth.magic_link.invalid"))
        |> redirect(to: ~p"/login")

      {:error, :expired} ->
        conn
        |> put_flash(:error, gettext("auth.magic_link.expired"))
        |> redirect(to: ~p"/login")

      {:error, :already_used} ->
        conn
        |> put_flash(:error, gettext("auth.magic_link.already_used"))
        |> redirect(to: ~p"/login")
    end
  end

  @doc """
  Déconnecte l'utilisateur et supprime le token de session de la base de données.

  Invalide également le cache de la session pour éviter qu'elle soit réutilisée.
  """
  def logout(conn, _params) do
    # Supprimer le token de session de la base de données
    session_token = get_session(conn, :session_token)

    _ =
      if session_token do
        # Invalider le cache de la session
        _ = Cachex.del(:portfolio_cache, {:session, session_token})

        case Auth.get_session_by_token(session_token) do
          nil -> :ok
          session -> _ = Auth.delete_session(session)
        end
      end

    conn
    |> clear_session()
    |> put_flash(:info, gettext("auth.logout.success"))
    |> redirect(to: ~p"/")
  end
end
