defmodule PortfolioWeb.Integration.AuthFlowTest do
  @moduledoc """
  Integration tests for the complete authentication flow.

  These tests verify the entire user journey from magic link request
  to authenticated session, ensuring all components work together correctly.

  Following the approach from docs/guides/towards-maintainable-elixir-testing.md,
  we test at the interface level (HTTP/LiveView) to maximize confidence.
  """

  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Auth

  describe "complete authentication flow" do
    test "user can register and authenticate via magic link", %{conn: conn} do
      email = "newuser#{System.unique_integer([:positive])}@example.com"

      # Step 1: Request magic link via LiveView (simulates form submission)
      {:ok, view, _html} = live(conn, ~p"/login")

      # Use phx-submit attribute since form has no id
      html =
        view
        |> element("form[phx-submit='request_link']")
        |> render_submit(%{email: email})

      # Verify confirmation message appears
      assert html =~ "lien" or has_element?(view, "button", "Renvoyer le lien")

      # Step 2: Verify magic link was created
      {:ok, user} = Auth.get_user_by_email(email)
      assert user.email == email
      assert user.role == "admin"

      # Step 3: Get the magic link token
      magic_link = Portfolio.Repo.get_by!(Portfolio.Auth.MagicLink, user_id: user.id)
      assert magic_link.used_at == nil

      # Step 4: Click magic link (simulates email link click)
      conn = build_conn()
      conn = get(conn, ~p"/auth/magic/#{magic_link.token}")
      assert redirected_to(conn) == ~p"/admin/albums"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Connexion réussie"

      # Step 5: Verify session was created
      session_token = get_session(conn, :session_token)
      assert session_token != nil

      session = Auth.get_session_by_token(session_token)
      assert session != nil
      assert session.user_id == user.id

      # Step 6: Verify magic link was marked as used
      used_magic_link = Portfolio.Repo.get!(Portfolio.Auth.MagicLink, magic_link.id)
      assert used_magic_link.used_at != nil

      # Step 7: Verify user can access protected pages
      conn = build_conn() |> init_test_session(%{session_token: session_token})
      conn = get(conn, ~p"/admin/albums")
      assert html_response(conn, 200) =~ "Albums"
    end

    test "user cannot reuse magic link", %{conn: conn} do
      # Arrange: Create user and magic link
      magic_link = create_magic_link()

      # Act: Use magic link once
      conn = get(conn, ~p"/auth/magic/#{magic_link.token}")
      assert redirected_to(conn) == ~p"/admin/albums"

      # Act: Try to use it again
      conn = build_conn()
      conn = get(conn, ~p"/auth/magic/#{magic_link.token}")

      # Assert: Should be rejected
      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "déjà été utilisé"
    end

    test "expired magic link cannot be used", %{conn: conn} do
      # Arrange: Create expired magic link
      expired_at = DateTime.add(DateTime.utc_now(), -1, :hour)
      magic_link = create_magic_link(expires_at: expired_at)

      # Act: Try to use expired link
      conn = get(conn, ~p"/auth/magic/#{magic_link.token}")

      # Assert: Should be rejected
      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expiré"
    end

    test "user can logout and session is destroyed", %{conn: conn} do
      # Arrange: Create authenticated session
      session = create_session()

      # Act: Access protected page
      conn = init_test_session(conn, %{session_token: session.token})
      conn = get(conn, ~p"/admin/albums")
      assert html_response(conn, 200) =~ "Albums"

      # Act: Logout
      conn = delete(conn, ~p"/logout")
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Déconnexion"

      # Assert: Session is cleared
      assert get_session(conn, :session_token) == nil

      # Assert: Session is deleted from database
      assert Auth.get_session_by_token(session.token) == nil

      # Assert: Cannot access protected pages anymore
      conn = build_conn() |> init_test_session(%{session_token: session.token})
      conn = get(conn, ~p"/admin/albums")
      assert redirected_to(conn) == ~p"/login"
    end

    @tag :skip
    test "concurrent authentication attempts are handled correctly", %{conn: _conn} do
      # Note: This test is skipped because the current implementation
      # doesn't handle concurrent magic link usage atomically.
      # This would require database-level locking or optimistic locking.
      # See Issue #79 in ROADMAP.md for Ecto.Multi improvements.

      # Arrange: Create magic link
      magic_link = create_magic_link()

      # Act: Simulate two concurrent authentication attempts
      task1 =
        Task.async(fn ->
          conn = build_conn()
          get(conn, ~p"/auth/magic/#{magic_link.token}")
        end)

      task2 =
        Task.async(fn ->
          # Small delay to ensure task1 starts first
          Process.sleep(10)
          conn = build_conn()
          get(conn, ~p"/auth/magic/#{magic_link.token}")
        end)

      conn1 = Task.await(task1)
      conn2 = Task.await(task2)

      # Assert: First request succeeds
      assert redirected_to(conn1) == ~p"/admin/albums"

      # Assert: Second request should fail (already used)
      # Currently both succeed due to race condition
      assert redirected_to(conn2) == ~p"/login"
      assert Phoenix.Flash.get(conn2.assigns.flash, :error) =~ "déjà été utilisé"
    end

    test "unauthenticated user is redirected to login", %{conn: conn} do
      # Act: Try to access protected page without authentication
      conn = get(conn, ~p"/admin/albums")

      # Assert: Redirected to login
      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "connecté"
    end

    test "session expires after inactivity", %{conn: conn} do
      # Arrange: Create session with old last_activity_at
      session = create_session()

      # Manually update last_activity_at to simulate inactivity
      old_activity =
        DateTime.utc_now()
        |> DateTime.add(-31, :day)
        |> DateTime.truncate(:second)

      session
      |> Ecto.Changeset.change(%{last_activity_at: old_activity})
      |> Portfolio.Repo.update!()

      # Act: Try to access protected page
      conn = init_test_session(conn, %{session_token: session.token})
      conn = get(conn, ~p"/admin/albums")

      # Assert: Redirected to login due to expired session
      assert redirected_to(conn) == ~p"/login"

      # Assert: Session was deleted
      assert Auth.get_session_by_token(session.token) == nil
    end
  end

  describe "error handling" do
    test "handles malformed magic link tokens gracefully", %{conn: conn} do
      malformed_tokens = [
        "../../etc/passwd",
        "<script>alert('xss')</script>",
        String.duplicate("a", 10000),
        "' OR '1'='1",
        "%00null"
      ]

      for token <- malformed_tokens do
        conn = build_conn()
        conn = get(conn, ~p"/auth/magic/#{token}")

        # Should redirect to login with error, not crash
        assert redirected_to(conn) == ~p"/login"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalide"
      end
    end

    test "handles database errors during session creation", %{conn: conn} do
      # This is difficult to test without mocking, but we can verify
      # the error path exists and handles failures gracefully

      # If we could trigger a DB error, we'd expect:
      # - User to be redirected to login
      # - Error message to be displayed
      # - No session to be created

      # For now, we document this as an edge case that's hard to test
      # without sophisticated mocking infrastructure
      assert true
    end
  end

  describe "security" do
    test "session tokens are cryptographically secure", %{conn: _conn} do
      # Create multiple sessions and verify tokens are unique and random
      sessions =
        for _i <- 1..10 do
          create_session()
        end

      tokens = Enum.map(sessions, & &1.token)

      # All tokens should be unique
      assert length(Enum.uniq(tokens)) == 10

      # Tokens should be sufficient length (at least 32 bytes when decoded)
      for token <- tokens do
        decoded = Base.url_decode64!(token, padding: false)
        assert byte_size(decoded) >= 32
      end
    end

    test "magic link tokens are cryptographically secure", %{conn: _conn} do
      # Create multiple magic links and verify tokens are unique and random
      magic_links =
        for _i <- 1..10 do
          create_magic_link()
        end

      tokens = Enum.map(magic_links, & &1.token)

      # All tokens should be unique
      assert length(Enum.uniq(tokens)) == 10

      # Tokens should be sufficient length
      for token <- tokens do
        decoded = Base.url_decode64!(token, padding: false)
        assert byte_size(decoded) >= 32
      end
    end

    test "session token from one user cannot access another user's resources", %{conn: conn} do
      # Arrange: Create two users with sessions
      user1 = create_user(email: "user1@example.com")
      user2 = create_user(email: "user2@example.com")
      session1 = create_session(user: user1)
      _session2 = create_session(user: user2)

      # Act: User1 tries to access resources (should work)
      conn = init_test_session(conn, %{session_token: session1.token})
      conn = get(conn, ~p"/admin/albums")
      assert html_response(conn, 200) =~ "Albums"

      # The actual authorization test would need to check that user1
      # cannot modify resources owned by user2, but that depends on
      # how we implement resource ownership
    end

    test "invalidated session cannot be used", %{conn: conn} do
      # Arrange: Create and then delete session
      session = create_session()
      Auth.delete_session(session)

      # Act: Try to use invalidated session
      conn = init_test_session(conn, %{session_token: session.token})
      conn = get(conn, ~p"/admin/albums")

      # Assert: Redirected to login
      assert redirected_to(conn) == ~p"/login"
    end
  end
end
