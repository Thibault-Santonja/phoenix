defmodule PortfolioWeb.Plugs.RateLimiter do
  @moduledoc """
  Plug pour limiter le nombre de requêtes par IP.

  Implémente un rate limiting global pour détecter les attaques distribuées,
  le scanning de l'application, ou l'abus de ressources.

  Configuration par défaut:
  - Limite: 100 requêtes par heure par IP
  - Window: 1 heure glissante

  ## Utilisation

      plug PortfolioWeb.Plugs.RateLimiter

  Ou avec configuration personnalisée:

      plug PortfolioWeb.Plugs.RateLimiter, limit: 200, window: :timer.hours(2)
  """

  import Plug.Conn
  import Phoenix.Controller

  alias PortfolioWeb.Plugs.IPUtils

  @behaviour Plug

  @default_limit 100
  @default_window :timer.hours(1)

  @impl Plug
  def init(opts) do
    %{
      limit: Keyword.get(opts, :limit, @default_limit),
      window: Keyword.get(opts, :window, @default_window)
    }
  end

  @impl Plug
  def call(conn, opts) do
    # Désactiver le rate limiting en environnement de test sauf si explicitement activé
    cond do
      # Desactive en environnement de test, sauf activation explicite.
      Application.get_env(:portfolio, :env) == :test and
          not Application.get_env(:portfolio, :enable_rate_limiting_in_tests, false) ->
        conn

      # La sonde de sante est exclue du plafond.
      #
      # Elle interroge ce chemin toutes les trois secondes depuis une seule et
      # meme adresse, celle du mandataire ou de la boucle locale : elle epuise
      # donc le quota a elle seule, et l'application se declare malade alors
      # qu'elle sert parfaitement les visiteurs. Constate en production : le
      # conteneur bascule en etat non sain avec un `429` en reponse a sa
      # propre sonde, pendant que le site repond `200`.
      #
      # L'exclusion porte sur le CHEMIN et jamais sur l'adresse d'origine :
      # une adresse se falsifie, un chemin non, et le point de sante ne rend
      # aucune donnee exploitable.
      conn.request_path == "/health" ->
        conn

      true ->
        ip = IPUtils.get_ip_address(conn)
        limit = opts.limit
        window = opts.window

        case check_rate_limit(ip, limit, window) do
          :ok ->
            conn

          {:error, :rate_limit_exceeded} ->
            conn
            |> put_status(:too_many_requests)
            |> put_view(html: PortfolioWeb.ErrorHTML)
            |> render("429.html")
            |> halt()
        end
    end
  end

  # Vérifie et incrémente le compteur de rate limit
  @spec check_rate_limit(String.t(), integer(), integer()) ::
          :ok | {:error, :rate_limit_exceeded}
  defp check_rate_limit(ip, limit, window) do
    cache_key = {:rate_limit, ip}
    window_ms = div(window, 1000)

    case Portfolio.CacheManager.get(cache_key) do
      {:ok, nil} ->
        # Première requête de cette IP dans la fenêtre
        _result = Portfolio.CacheManager.put(cache_key, 1, ttl: window_ms)
        :ok

      {:ok, count} ->
        if count < limit do
          # Incrémente le compteur (retourne la nouvelle valeur)
          _result = Portfolio.CacheManager.incr(cache_key)
          :ok
        else
          # Limite dépassée
          {:error, :rate_limit_exceeded}
        end

      _error ->
        # En cas d'erreur cache, on laisse passer (fail open)
        :ok
    end
  end
end
