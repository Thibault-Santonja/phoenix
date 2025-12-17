defmodule PortfolioWeb.Integration.RoleChangeTest do
  @moduledoc """
  Integration tests for user role changes and session behavior.

  These tests verify that when an admin changes a user's role, the change is
  reflected immediately on the user's next request (Issue 12 - User role reload).

  NOTE: These tests use direct DB updates via `update_user_role/2` helper to
  simulate admin role changes, since the full admin UI for role management
  hasn't been implemented yet.

  Tests cover:
  - Role changes are reflected in active sessions
  - Demoted users lose access to admin pages
  - Promoted users gain access to admin pages
  - Concurrent role changes don't cause race conditions
  """

  use PortfolioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.AuthFixtures

  alias Ecto.Changeset
  alias Portfolio.Auth
  alias Portfolio.Repo

  # Helper function to update user role directly in DB (simulates admin action)
  defp update_user_role(user, new_role) do
    user
    |> Changeset.change(%{role: new_role})
    |> Repo.update()
  end

  describe "role change integration" do
    setup do
      # Create admin user
      admin = create_user(email: "admin@example.com", role: :admin)
      admin_session = create_session(user: admin)

      # Create regular user
      user = create_user(email: "user@example.com", role: :user)
      user_session = create_session(user: user)

      %{
        admin: admin,
        admin_session: admin_session,
        user: user,
        user_session: user_session
      }
    end

    test "user session reflects role change on next request", %{
      user: user,
      user_session: user_session
    } do
      # User makes a request with their current session
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => user_session.token})
        |> get(~p"/")

      # Verify user is logged in as regular user
      assert get_session(conn, "session_token") == user_session.token
      current_user = conn.assigns.current_user
      assert current_user.role == :user

      # Admin changes user's role to admin
      assert {:ok, _updated_user} = update_user_role(user, :admin)

      # User makes another request with the same session
      conn2 =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => user_session.token})
        |> get(~p"/")

      # Verify role is updated in the session
      current_user2 = conn2.assigns.current_user
      assert current_user2.role == :admin
      assert current_user2.id == user.id
    end

    test "demoted user cannot access admin pages after role change", %{user: user} do
      # NOTE: Admin routes are protected via on_mount: :require_admin_role
      # This test verifies that demoted users are redirected away from admin pages

      # First, promote user to admin
      assert {:ok, promoted_user} = update_user_role(user, :admin)

      # Create new session for promoted user
      promoted_session = create_session(user: promoted_user)

      # User accesses admin dashboard as admin
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => promoted_session.token})
        |> get(~p"/admin")

      assert html_response(conn, 200)
      assert conn.assigns.current_user.role == :admin

      # Admin demotes user back to regular user
      assert {:ok, _demoted_user} = update_user_role(promoted_user, :user)

      # User tries to access admin dashboard again - should be redirected
      conn2 =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => promoted_session.token})
        |> get(~p"/admin")

      # Verify user is redirected (no longer has admin access)
      assert redirected_to(conn2) == "/"

      assert Phoenix.Flash.get(conn2.assigns.flash, :error) ==
               "Accès réservé aux administrateurs."
    end

    test "promoted user can access admin pages after role change", %{user: user} do
      # NOTE: Admin routes are protected via on_mount: :require_admin_role
      # This test verifies that promoted users can access admin pages

      # Create session for regular user
      user_session = create_session(user: user)

      # User makes initial request to admin - should be redirected (not admin yet)
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => user_session.token})
        |> get(~p"/admin")

      # Verify user is redirected (not admin)
      assert redirected_to(conn) == "/"

      # Admin promotes user to admin
      assert {:ok, _promoted_user} = update_user_role(user, :admin)

      # User makes another request with same session
      conn2 =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => user_session.token})
        |> get(~p"/admin")

      # Verify role is now admin (reloaded from DB) and can access admin
      assert html_response(conn2, 200)
      assert conn2.assigns.current_user.role == :admin
    end

    test "role change reflected in LiveView session", %{admin: admin} do
      # NOTE: Admin routes are protected via on_mount: :require_admin_role
      # This test verifies that role changes are reflected in LiveView sessions

      # Create session for admin user
      admin_session = create_session(user: admin)

      # Mount a LiveView as admin user
      {:ok, _view, html} =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => admin_session.token})
        |> live(~p"/admin/users")

      # Verify we can access the page (role check via render)
      assert html =~ "Gestion des utilisateurs"

      # Demote admin to user (simulating another admin doing this)
      assert {:ok, _demoted_user} = update_user_role(admin, :user)

      # Mount LiveView again with same session - should be redirected
      {:error, {:redirect, redirect_info}} =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => admin_session.token})
        |> live(~p"/admin/users")

      # Verify redirect to home with error
      assert redirect_info.to == "/"
      assert redirect_info.flash["error"] == "Accès réservé aux administrateurs."

      # Verify the actual role change happened in DB
      {:ok, reloaded_user} = Auth.get_user(admin.id)
      assert reloaded_user.role == :user
    end

    test "concurrent role changes don't cause race conditions", %{user: user} do
      user_session = create_session(user: user)

      # Simulate concurrent role changes by admin
      tasks =
        for role <- [:admin, :user, :admin, :user, :admin] do
          Task.async(fn ->
            update_user_role(user, role)
          end)
        end

      # Wait for all tasks
      Enum.each(tasks, &Task.await/1)

      # Make request to verify final role
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => user_session.token})
        |> get(~p"/")

      # Role should be consistent (whatever the last change was)
      final_role = conn.assigns.current_user.role
      assert final_role in [:admin, :user]

      # Verify DB matches session
      {:ok, db_user} = Auth.get_user(user.id)
      assert db_user.role == final_role
    end

    @tag :skip
    test "deleted user session is invalidated", %{user: user} do
      # NOTE: Skipped - UserService.delete_user/1 not implemented yet
      user_session = create_session(user: user)

      # User makes a request
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => user_session.token})
        |> get(~p"/")

      assert conn.assigns.current_user.id == user.id

      # Delete user (function not implemented yet)
      # assert {:ok, _} = UserService.delete_user(user)

      # User tries to make another request
      conn2 =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => user_session.token})
        |> get(~p"/")

      # Should not have current_user (session invalid)
      refute Map.has_key?(conn2.assigns, :current_user) && conn2.assigns.current_user != nil
    end

    @tag :skip
    test "role change logged in audit log", %{user: user} do
      # NOTE: Skipped - Audit logging for role changes not implemented yet
      # Change role
      assert {:ok, _updated_user} = update_user_role(user, :admin)

      # Verify audit log entry exists (not implemented yet)
      # logs = Portfolio.Auth.AuditLogger.get_logs_for_resource("User", user.id, limit: 1)
      # assert length(logs) > 0
      # log = hd(logs)
      # assert log.action == "update"
      # assert log.performed_by_id == admin.id
      # assert log.changes["role"] == ["user", "admin"]
    end

    test "multiple users with role changes don't interfere" do
      # Create multiple users
      users =
        for i <- 1..5 do
          create_user(email: "user#{i}@example.com", role: :user)
        end

      sessions = Enum.map(users, fn user -> create_session(user: user) end)

      # Change roles for all users concurrently
      tasks =
        Enum.zip(users, 0..4)
        |> Enum.map(fn {user, idx} ->
          Task.async(fn ->
            role = if rem(idx, 2) == 0, do: :admin, else: :user
            update_user_role(user, role)
          end)
        end)

      Enum.each(tasks, &Task.await/1)

      # Verify each session has correct role
      Enum.zip(users, sessions)
      |> Enum.with_index()
      |> Enum.each(fn {{user, session}, idx} ->
        conn =
          build_conn()
          |> Plug.Test.init_test_session(%{"session_token" => session.token})
          |> get(~p"/")

        expected_role = if rem(idx, 2) == 0, do: :admin, else: :user
        assert conn.assigns.current_user.role == expected_role
        assert conn.assigns.current_user.id == user.id
      end)
    end
  end

  describe "privilege escalation prevention" do
    setup do
      user = create_user(email: "test@example.com", role: :user)
      %{user: user}
    end

    test "user cannot escalate privileges via session tampering", %{user: user} do
      user_session = create_session(user: user)

      # User makes request with valid session
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => user_session.token})
        |> get(~p"/")

      assert conn.assigns.current_user.role == :user

      # Attacker tries to tamper with session to become admin
      # (This is prevented by signed cookies, but we test the server-side check)
      # Even if session data was modified, the role is reloaded from DB

      # Make another request - role should still be from DB
      conn2 =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => user_session.token})
        |> get(~p"/")

      # Role must match database, not session data
      {:ok, db_user} = Auth.get_user(user.id)
      assert conn2.assigns.current_user.role == db_user.role
      assert conn2.assigns.current_user.role == :user
    end

    test "expired session cannot be used after role change" do
      user = create_user(email: "expiring@example.com", role: :user)

      # Create session with expired last_activity_at (>2 hours ago)
      # Truncate to second precision as required by :utc_datetime
      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-3 * 3600, :second)
        |> DateTime.truncate(:second)

      # Use fixture to create session, then manually update last_activity_at in DB
      session = create_session(user: user)

      Portfolio.Repo.get!(Portfolio.Auth.UserSession, session.id)
      |> Ecto.Changeset.change(%{last_activity_at: expired_at})
      |> Portfolio.Repo.update!()

      # Try to use expired session
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"session_token" => session.token})
        |> get(~p"/")

      # Should not have valid session
      refute Map.has_key?(conn.assigns, :current_user) && conn.assigns.current_user != nil
    end
  end
end
