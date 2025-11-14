defmodule PortfolioWeb.AuthHelpers do
  @moduledoc """
  Helpers partagés pour l'authentification entre Plugs et LiveViews.

  Ce module centralise la logique commune d'authentification utilisée par:
  - PortfolioWeb.Plugs.RequireAuth (pour les controllers)
  - PortfolioWeb.UserAuth (pour les LiveViews)

  Cela évite la duplication de code et garantit un comportement cohérent.
  """

  alias Portfolio.Auth
  alias Portfolio.Auth.UserSession

  @doc """
  Récupère l'utilisateur et la session depuis un token de session.

  Gère automatiquement:
  - La récupération depuis le cache (en production)
  - Le rechargement du user pour avoir des données fraîches
  - La mise à jour de l'activité de session

  Retourne `{user, session}` si trouvé, `nil` sinon.
  """
  @spec fetch_user_from_session_token(String.t() | nil) ::
          {Portfolio.Auth.User.t(), UserSession.t()} | nil
  def fetch_user_from_session_token(nil), do: nil

  def fetch_user_from_session_token(session_token) when is_binary(session_token) do
    case fetch_session_from_cache(session_token) do
      nil ->
        nil

      session ->
        # Recharger le user pour avoir des données fraîches (notamment le role)
        fresh_session = Auth.reload_user(session)

        # Mettre à jour l'activité de la session
        update_session_activity_async(fresh_session)

        {fresh_session.user, fresh_session}
    end
  end

  # Récupère une session depuis le cache ou la base de données
  defp fetch_session_from_cache(session_token) do
    # En test, skip le cache pour éviter la pollution entre tests
    if Mix.env() == :test do
      Auth.get_session_by_token(session_token)
    else
      fetch_session_with_cache(session_token)
    end
  end

  # Récupère une session avec le cache Cachex
  defp fetch_session_with_cache(session_token) do
    hashed_token = UserSession.hash_token_value(session_token)
    cache_key = {:session, hashed_token}

    case Cachex.fetch(:portfolio_cache, cache_key, fn ->
           get_session_for_cache(session_token)
         end) do
      {:ok, session} -> session
      {:commit, session} -> session
      {:ignore, nil} -> nil
      _ -> nil
    end
  end

  # Récupère une session pour mise en cache
  defp get_session_for_cache(session_token) do
    case Auth.get_session_by_token(session_token) do
      nil ->
        {:ignore, nil}

      session ->
        {:commit, session, ttl: :timer.hours(1)}
    end
  end

  # Met à jour l'activité de la session de manière asynchrone en production
  defp update_session_activity_async(session) do
    if Mix.env() == :test do
      Auth.update_session_activity(session)
    else
      Task.start(fn -> Auth.update_session_activity(session) end)
    end
  end
end
