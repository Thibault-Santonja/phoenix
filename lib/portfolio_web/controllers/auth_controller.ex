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
       when action in [:verify_magic_link]

  @doc """
  Vérifie un magic link et authentifie l'utilisateur.

  Crée un token de session en base de données pour permettre:
  - La révocation de sessions spécifiques
  - L'expiration après 30 jours d'inactivité
  - Le tracking des sessions actives
  """
  def verify_magic_link(conn, %{"token" => token}) do
    case Auth.verify_magic_link(token) do
      {:ok, user} ->
        # Créer un token de session en base de données
        case Auth.create_session(user) do
          {:ok, session} ->
            conn
            |> put_session(:session_token, session.token)
            |> put_flash(:info, "Connexion réussie ! Bienvenue #{user.email}")
            |> redirect(to: ~p"/admin")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Erreur lors de la création de la session.")
            |> redirect(to: ~p"/login")
        end

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, "Lien de connexion invalide.")
        |> redirect(to: ~p"/login")

      {:error, :expired} ->
        conn
        |> put_flash(:error, "Ce lien de connexion a expiré. Demandez un nouveau lien.")
        |> redirect(to: ~p"/login")

      {:error, :already_used} ->
        conn
        |> put_flash(:error, "Ce lien de connexion a déjà été utilisé. Demandez un nouveau lien.")
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

    if session_token do
      # Invalider le cache de la session
      Cachex.del(:portfolio_cache, {:session, session_token})

      case Auth.get_session_by_token(session_token) do
        nil -> :ok
        session -> Auth.delete_session(session)
      end
    end

    conn
    |> clear_session()
    |> put_flash(:info, "Déconnexion réussie.")
    |> redirect(to: ~p"/")
  end
end
