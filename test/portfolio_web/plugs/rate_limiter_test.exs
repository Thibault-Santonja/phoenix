defmodule PortfolioWeb.Plugs.RateLimiterTest do
  use PortfolioWeb.ConnCase, async: false

  alias PortfolioWeb.Plugs.RateLimiter

  setup do
    # Activer le rate limiting pour ces tests spécifiques
    Application.put_env(:portfolio, :enable_rate_limiting_in_tests, true)

    # Nettoyer le cache avant chaque test pour éviter les interférences
    Cachex.clear(:portfolio_cache)

    on_exit(fn ->
      # Désactiver le rate limiting après les tests
      Application.put_env(:portfolio, :enable_rate_limiting_in_tests, false)
    end)

    :ok
  end

  describe "rate limiting" do
    test "allows requests under the limit", %{conn: conn} do
      opts = RateLimiter.init(limit: 5, window: :timer.minutes(1))

      # Faire 5 requêtes (sous la limite)
      Enum.each(1..5, fn _ ->
        result_conn = RateLimiter.call(conn, opts)
        refute result_conn.halted
      end)
    end

    test "blocks requests over the limit", %{conn: conn} do
      opts = RateLimiter.init(limit: 3, window: :timer.minutes(1))

      # Faire 3 requêtes (limite)
      Enum.each(1..3, fn _ ->
        result_conn = RateLimiter.call(conn, opts)
        refute result_conn.halted
      end)

      # La 4ème requête doit être bloquée
      result_conn = RateLimiter.call(conn, opts)
      assert result_conn.halted
      assert result_conn.status == 429
    end

    test "rate limit is per IP address", %{conn: conn} do
      opts = RateLimiter.init(limit: 2, window: :timer.minutes(1))

      # IP 1 fait 2 requêtes (limite atteinte)
      conn1 = %{conn | remote_ip: {192, 168, 1, 1}}

      Enum.each(1..2, fn _ ->
        result_conn = RateLimiter.call(conn1, opts)
        refute result_conn.halted
      end)

      # IP 1 bloquée à la 3ème requête
      result_conn = RateLimiter.call(conn1, opts)
      assert result_conn.halted

      # IP 2 peut encore faire des requêtes
      conn2 = %{conn | remote_ip: {192, 168, 1, 2}}
      result_conn = RateLimiter.call(conn2, opts)
      refute result_conn.halted
    end

    test "rate limit resets after window expires", %{conn: conn} do
      # Window très courte (1 seconde) pour le test
      opts = RateLimiter.init(limit: 2, window: 1000)

      # Faire 2 requêtes (limite)
      Enum.each(1..2, fn _ ->
        result_conn = RateLimiter.call(conn, opts)
        refute result_conn.halted
      end)

      # 3ème requête bloquée
      result_conn = RateLimiter.call(conn, opts)
      assert result_conn.halted

      # Attendre que la fenêtre expire
      Process.sleep(1100)

      # Nouvelle requête doit passer
      result_conn = RateLimiter.call(conn, opts)
      refute result_conn.halted
    end

    test "uses default configuration when not specified", %{conn: _conn} do
      opts = RateLimiter.init([])

      # Devrait avoir limit: 100, window: 1 heure
      assert opts.limit == 100
      assert opts.window == :timer.hours(1)
    end

    test "respects X-Forwarded-For header", %{conn: conn} do
      opts = RateLimiter.init(limit: 2, window: :timer.minutes(1))

      # Simuler des requêtes derrière un proxy
      conn_with_proxy = put_req_header(conn, "x-forwarded-for", "203.0.113.1, 198.51.100.1")

      # Faire 2 requêtes (limite)
      Enum.each(1..2, fn _ ->
        result_conn = RateLimiter.call(conn_with_proxy, opts)
        refute result_conn.halted
      end)

      # 3ème requête bloquée
      result_conn = RateLimiter.call(conn_with_proxy, opts)
      assert result_conn.halted

      # Une autre IP dans X-Forwarded-For peut faire des requêtes
      conn_other_ip = put_req_header(conn, "x-forwarded-for", "203.0.113.2")
      result_conn = RateLimiter.call(conn_other_ip, opts)
      refute result_conn.halted
    end
  end
end
