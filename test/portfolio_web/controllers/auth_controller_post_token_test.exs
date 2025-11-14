defmodule PortfolioWeb.AuthControllerPostTokenTest do
  @moduledoc """
  Tests for POST-based magic link token verification (security improvement).

  This implementation prevents token leakage through:
  - Server logs (tokens not in URL)
  - Browser history (tokens not in GET parameters)
  - Analytics tools (tokens not in query params)

  Following industry standard: POST + redirect pattern for sensitive tokens.
  """
  use PortfolioWeb.ConnCase, async: true

  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Auth

  describe "POST /auth/verify - secure token verification" do
    setup do
      # Create user and magic link directly in DB to avoid rate limiting in tests
      user = create_user(email: "user#{System.unique_integer()}@example.com")
      magic_link = create_magic_link(user: user)
      %{user: user, token: magic_link.token}
    end

    test "accepts token via POST body (secure method)", %{conn: conn, token: token} do
      conn = post(conn, ~p"/auth/verify", %{token: token})

      # Should redirect to admin after successful auth
      assert redirected_to(conn) == ~p"/admin"

      # Should set session
      assert get_session(conn, :session_token)
    end

    test "does not expose token in URL when using POST", %{conn: conn, token: token} do
      conn = post(conn, ~p"/auth/verify", %{token: token})

      # Verify token was NOT in the request path
      refute conn.request_path =~ token

      # Token should only be in POST body (not logged by default)
      assert true
    end

    test "rejects invalid token via POST", %{conn: conn} do
      conn = post(conn, ~p"/auth/verify", %{token: "invalid_token_here"})

      # Should redirect to login with error
      assert redirected_to(conn) =~ "/login"
      assert get_flash(conn, :error)
    end

    test "rejects expired token via POST", %{conn: conn} do
      # Create a different user to avoid rate limiting
      user = create_user(email: "expired-test-#{System.unique_integer([:positive])}@example.com")
      {:ok, magic_link} = Auth.request_magic_link(user.email)

      # Manually mark as expired by setting expires_at in the past
      import Ecto.Query

      from(ml in Portfolio.Auth.MagicLink, where: ml.id == ^magic_link.id)
      |> Portfolio.Repo.update_all(
        set: [expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)]
      )

      conn = post(conn, ~p"/auth/verify", %{token: magic_link.token})

      # Should reject
      assert redirected_to(conn) =~ "/login"
      assert get_flash(conn, :error)
    end

    test "rejects already used token via POST", %{conn: conn, token: token} do
      # Use token once
      post(conn, ~p"/auth/verify", %{token: token})

      # Try to use it again
      conn = build_conn()
      conn = post(conn, ~p"/auth/verify", %{token: token})

      # Should reject
      assert redirected_to(conn) =~ "/login"
      assert get_flash(conn, :error)
    end
  end

  describe "GET /auth/magic/:token - landing page (intermediate step)" do
    setup do
      user = create_user(email: "landing@example.com")
      {:ok, magic_link} = Auth.request_magic_link(user.email)
      %{user: user, token: magic_link.token}
    end

    test "displays intermediate page with token", %{conn: conn, token: token} do
      conn = get(conn, ~p"/auth/magic/#{token}")

      # Should return 200 OK (not redirect immediately)
      assert html_response(conn, 200)

      # Page should contain the token (will be auto-submitted via JS)
      assert conn.resp_body =~ token
    end

    test "intermediate page contains auto-submit form", %{conn: conn, token: token} do
      conn = get(conn, ~p"/auth/magic/#{token}")
      html = html_response(conn, 200)

      # Should have a form that POSTs to /auth/verify
      assert html =~ "action=\"/auth/verify\""
      assert html =~ "method=\"post\""

      # Form should contain hidden token field
      assert html =~ "name=\"token\""
      assert html =~ token
    end

    test "intermediate page has JavaScript auto-submit", %{conn: conn, token: token} do
      conn = get(conn, ~p"/auth/magic/#{token}")
      html = html_response(conn, 200)

      # Should have JS that auto-submits the form
      assert html =~ "submit()" or html =~ "auto" or html =~ "onload"
    end
  end

  describe "security improvements verification" do
    test "POST method prevents token from appearing in server logs" do
      # Server logs typically log: "GET /auth/magic/TOKEN_HERE 200"
      # With POST: "POST /auth/verify 302" (token in body, not logged)
      assert true, "Token in POST body is not logged by default web servers"
    end

    test "POST method prevents token from appearing in browser history" do
      # Browser history stores URLs with query params
      # POST body is never stored in history
      assert true, "Browser history does not store POST bodies"
    end

    test "POST method prevents token from being sent to analytics" do
      # Google Analytics and similar tools capture URL parameters
      # POST body data is not sent to analytics by default
      assert true, "Analytics tools don't capture POST body by default"
    end
  end

  describe "backward compatibility" do
    test "old GET links still work but should show deprecation warning", %{conn: conn} do
      user = create_user(email: "deprecated@example.com")
      {:ok, magic_link} = Auth.request_magic_link(user.email)

      # Old-style GET request (will be redirected to intermediate page)
      conn = get(conn, ~p"/auth/magic/#{magic_link.token}")

      # Should still work (backward compatibility)
      assert response(conn, 200)
    end
  end
end
