defmodule PortfolioWeb.Integration.CsrfProtectionTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.Template

  describe "CSRF error page rendering" do
    test "403 error renders custom error page", %{conn: _conn} do
      # Since we can't easily trigger real CSRF in tests (LiveView skips it),
      # we test the error page rendering directly
      html = render_to_string(PortfolioWeb.ErrorHTML, "403", "html", [])

      assert html =~ "403"
      assert html =~ "Requête non autorisée"
      assert html =~ "session"
    end

    test "403 page provides helpful explanation", %{conn: _conn} do
      html = render_to_string(PortfolioWeb.ErrorHTML, "403", "html", [])

      # Should explain common causes
      assert html =~ "inactif" or html =~ "expiré"
      assert html =~ "sécurité"
    end

    test "403 page provides actionable links", %{conn: _conn} do
      html = render_to_string(PortfolioWeb.ErrorHTML, "403", "html", [])

      # Should have navigation options
      assert html =~ "href=\"/\""
      assert html =~ "Retour à l'accueil"
      assert html =~ "Réessayer"
    end

    test "403 page does not expose technical details", %{conn: _conn} do
      html = render_to_string(PortfolioWeb.ErrorHTML, "403", "html", [])

      # Should not reveal security implementation
      refute html =~ "_csrf_token"
      refute html =~ "Plug.CSRFProtection"
      refute html =~ "ForbiddenError"
      refute html =~ "stacktrace"
    end

    test "403 page has proper visual design", %{conn: _conn} do
      html = render_to_string(PortfolioWeb.ErrorHTML, "403", "html", [])

      # Should have Tailwind classes and structure
      assert html =~ "bg-"
      assert html =~ "text-"
      assert html =~ "rounded"
      assert html =~ "<svg"
    end
  end

  describe "meta tag CSRF token" do
    test "CSRF meta tag is present in HTML responses", %{conn: conn} do
      conn = get(conn, ~p"/")

      # Meta tag should be in the response
      assert conn.resp_body =~ ~r/<meta name="csrf-token" content="[^"]+"/
    end

    test "CSRF meta tag contains valid token", %{conn: conn} do
      conn = get(conn, ~p"/")

      # Extract token from meta tag
      [_, meta_token] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, conn.resp_body)

      # Should be a valid token (long string)
      assert is_binary(meta_token)
      assert String.length(meta_token) > 20
    end
  end

  describe "CSRF protection is enabled" do
    test "protect_from_forgery plug is present in router", %{conn: conn} do
      # Verify CSRF protection is configured by checking that
      # the plug is in the before_send callbacks
      conn = get(conn, ~p"/")

      # The Plug.CSRFProtection should add a before_send callback
      before_send_callbacks = conn.private[:before_send] || []

      # Check that there's a CSRF-related callback
      has_csrf_protection =
        Enum.any?(before_send_callbacks, fn callback ->
          callback
          |> Function.info(:module)
          |> elem(1)
          |> to_string()
          |> String.contains?("CSRF")
        end)

      assert has_csrf_protection, "CSRF protection should be enabled"
    end

    test "session contains CSRF token after GET request", %{conn: conn} do
      conn = get(conn, ~p"/")

      # Session should contain CSRF token
      session = conn.private[:plug_session]
      assert session["_csrf_token"], "Session should contain CSRF token"
    end
  end
end
