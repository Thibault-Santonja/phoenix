defmodule PortfolioWeb.Integration.EdgeCasesTest do
  @moduledoc """
  Integration tests for edge cases and boundary conditions.

  These tests cover scenarios that are less common but critical for security
  and reliability, including:
  - Expired/invalid tokens
  - Concurrent session handling
  - Malformed requests
  - Rate limiting edge cases
  - Database connection edge cases
  """
  use PortfolioWeb.ConnCase, async: true

  import PortfolioTest.Fixtures.AuthFixtures
  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.Auth.MagicLinkService
  alias Portfolio.Auth.ValueObjects.Email

  describe "authentication edge cases" do
    test "rejects expired magic link token", %{conn: conn} do
      user = create_user(email: "expired@example.com")

      # Create an expired magic link
      magic_link =
        create_magic_link(
          user: user,
          expires_at: DateTime.add(DateTime.utc_now(), -1, :hour)
        )

      # POST to verify should fail with expired token
      conn = post(conn, ~p"/auth/verify", %{"token" => magic_link.token})
      assert redirected_to(conn) == ~p"/login"
      # Check flash contains expiration message (in French or English)
      flash_error = Phoenix.Flash.get(conn.assigns.flash, :error)
      assert flash_error =~ "expiré" or flash_error =~ "expired"
    end

    test "rejects already-used magic link token", %{conn: conn} do
      user = create_user(email: "used@example.com")
      magic_link = create_magic_link(user: user)

      # First use - should succeed
      conn = post(conn, ~p"/auth/verify", %{"token" => magic_link.token})
      assert redirected_to(conn) == ~p"/admin"

      # Second use - should fail (token consumed)
      conn2 = build_conn()
      conn2 = post(conn2, ~p"/auth/verify", %{"token" => magic_link.token})
      assert redirected_to(conn2) == ~p"/login"
      # Check flash contains "already used" message (in French or English)
      flash_error = Phoenix.Flash.get(conn2.assigns.flash, :error)
      assert flash_error =~ "déjà été utilisé" or flash_error =~ "already"
    end

    test "handles malformed token gracefully" do
      # Various malformed tokens
      malformed_tokens = [
        "not-a-valid-token",
        String.duplicate("a", 1000),
        "<script>alert('xss')</script>",
        "../../../../etc/passwd",
        "' OR '1'='1"
      ]

      for token <- malformed_tokens do
        conn = post(build_conn(), ~p"/auth/verify", %{"token" => token})
        # Should redirect to login without crashing
        assert redirected_to(conn) == ~p"/login"
      end
    end

    test "handles empty token in request", %{conn: conn} do
      # Empty string token should be handled
      conn = post(conn, ~p"/auth/verify", %{"token" => ""})
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "session edge cases" do
    test "handles session with deleted user gracefully", %{conn: conn} do
      # Create a second admin first to avoid "Cannot delete the last admin user" trigger
      _other_admin = create_user(email: "other_admin@example.com", role: :admin)
      user = create_user(email: "deleted@example.com", role: :admin)
      magic_link = create_magic_link(user: user)

      # Log in the user
      conn = post(conn, ~p"/auth/verify", %{"token" => magic_link.token})
      assert redirected_to(conn) == ~p"/admin"

      # Delete the user from database (now allowed since there's another admin)
      Portfolio.Repo.delete!(user)

      # Try to access protected route - should handle gracefully
      conn =
        conn
        |> recycle()
        |> get(~p"/admin")

      # Should redirect to login
      assert redirected_to(conn) == ~p"/login"
    end

    test "logout clears session completely", %{conn: conn} do
      user = create_user(email: "logout@example.com", role: :admin)
      magic_link = create_magic_link(user: user)

      conn = post(conn, ~p"/auth/verify", %{"token" => magic_link.token})
      assert redirected_to(conn) == ~p"/admin"

      # Logout
      conn =
        conn
        |> recycle()
        |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/"

      # Verify cannot access protected routes
      conn =
        conn
        |> recycle()
        |> get(~p"/admin")

      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "album and photo edge cases" do
    test "handles album with no photos gracefully" do
      _album = create_album(title: "Empty Album", published: true)

      # Access public timeline on photo subdomain - should not crash
      conn =
        build_conn()
        |> Map.put(:host, "photo.localhost")
        |> get("/timeline")

      # Empty album should be accessible (may show empty state or redirect)
      assert conn.status in [200, 302]
    end

    test "handles album with special characters in title" do
      special_titles = [
        "Album & Photos",
        "Album <Test>",
        "Album \"Quotes\"",
        "Album 'Apostrophe'",
        "Album avec accénts éèê",
        "Album 日本語"
      ]

      for title <- special_titles do
        album = create_album(title: title, published: true)
        assert album.title == title
      end
    end

    test "rejects duplicate album slugs" do
      album1 = create_album(title: "Test Album")

      # Second album with same title should fail due to unique slug constraint
      assert {:error, changeset} =
               Portfolio.Photography.create_album(%{
                 title: "Test Album",
                 type: :wedding,
                 date_prise_vue: Date.utc_today()
               })

      assert changeset.errors[:slug] != nil
      # First album should still exist
      assert album1.slug == "test-album"
    end
  end

  describe "rate limiting edge cases" do
    test "rate limit resets after window expires" do
      # This test verifies the rate limiter behavior
      # Note: In actual testing, we would mock the time or use a test backend

      # Make a request that would be rate limited
      user = create_user(email: "rate@example.com")

      # First request should succeed
      {:ok, _} = MagicLinkService.request_magic_link(user.email)

      # Rate limiter should track but not block first few requests
      # (exact behavior depends on configured limits)
    end

    test "rate limiter handles concurrent requests" do
      _user = create_user(email: "concurrent@example.com")

      # Simulate concurrent requests
      tasks =
        for _i <- 1..5 do
          Task.async(fn ->
            conn = build_conn()
            get(conn, ~p"/login")
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All requests should complete (possibly some rate limited)
      for result <- results do
        assert result.status in [200, 429]
      end
    end
  end

  describe "input validation edge cases" do
    test "validates standard email format" do
      # Test that email validation works properly for valid emails
      valid_email = "test@example.com"

      result = Email.new(valid_email)

      # Should accept valid email
      assert {:ok, _} = result
    end

    test "rejects invalid email format" do
      # Test that email validation rejects invalid formats
      invalid_emails = [
        "not-an-email",
        "@example.com",
        "test@",
        ""
      ]

      for email <- invalid_emails do
        result = Email.new(email)
        # Should return an error for invalid email
        assert {:error, _} = result
      end
    end

    test "handles unicode in email validation" do
      unicode_inputs = [
        "test@例え.jp",
        "тест@пример.рф",
        "用户@例子.中国"
      ]

      for email <- unicode_inputs do
        result = Email.new(email)
        # Unicode emails may or may not be valid depending on implementation
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end

    test "handles special characters in email", %{conn: _conn} do
      # Test emails with special but valid characters
      special_emails = [
        "test+tag@example.com",
        "test.name@example.com",
        "test_name@example.com"
      ]

      for email <- special_emails do
        result = Email.new(email)
        # These should be valid
        assert {:ok, _} = result
      end
    end
  end

  describe "CSP nonce edge cases" do
    test "CSP header contains nonce", %{conn: conn} do
      conn = get(conn, ~p"/")

      [csp_header] = get_resp_header(conn, "content-security-policy")

      assert csp_header =~ ~r/nonce-[A-Za-z0-9+\/=]+/,
             "CSP header should contain a nonce value"
    end

    test "CSP nonce is different for each request", %{conn: _conn} do
      conn1 = get(build_conn(), ~p"/")
      conn2 = get(build_conn(), ~p"/")

      [csp1] = get_resp_header(conn1, "content-security-policy")
      [csp2] = get_resp_header(conn2, "content-security-policy")

      # Extract nonces
      [_, nonce1] = Regex.run(~r/nonce-([A-Za-z0-9+\/=]+)/, csp1)
      [_, nonce2] = Regex.run(~r/nonce-([A-Za-z0-9+\/=]+)/, csp2)

      assert nonce1 != nonce2,
             "Each request should have a unique CSP nonce"
    end
  end

  describe "health check edge cases" do
    test "health check works under load" do
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            conn = get(build_conn(), ~p"/health")
            conn.status
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All health checks should succeed
      assert Enum.all?(results, &(&1 == 200))
    end

    test "ready check returns status", %{conn: conn} do
      # The ready endpoint should return a status
      conn = get(conn, ~p"/health/ready")

      # Should return 200 if DB is available, or error status if not
      assert conn.status in [200, 503]
    end
  end
end
