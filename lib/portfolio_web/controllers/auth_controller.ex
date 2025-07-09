defmodule PortfolioWeb.AuthController do
  @moduledoc """
  Controller pour l'authentification via magic links.
  """

  use PortfolioWeb, :controller

  alias Portfolio.Auth

  @doc """
  Vérifie un magic link et authentifie l'utilisateur.
  """
  def verify_magic_link(conn, %{"token" => token}) do
    case Auth.verify_magic_link(token) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Connexion réussie ! Bienvenue #{user.email}")
        |> redirect(to: ~p"/admin/albums")

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
  Déconnecte l'utilisateur.
  """
  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Déconnexion réussie.")
    |> redirect(to: ~p"/")
  end
end
