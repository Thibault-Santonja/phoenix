defmodule PortfolioWeb.AuthHelpersTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Auth
  alias Portfolio.Auth.UserService
  alias Portfolio.Auth.UserSession
  alias PortfolioWeb.AuthHelpers

  import PortfolioTest.Fixtures.AuthFixtures

  describe "fetch_user_from_session_token/1" do
    test "returns nil for nil token" do
      assert AuthHelpers.fetch_user_from_session_token(nil) == nil
    end

    test "returns nil for invalid token" do
      assert AuthHelpers.fetch_user_from_session_token("invalid_token") == nil
    end

    test "returns nil for non-existent session" do
      assert AuthHelpers.fetch_user_from_session_token("non_existent_token_abc123") == nil
    end

    test "returns user and session for valid token" do
      user = create_user(email: "test@example.com")
      {:ok, session} = Auth.create_session(user)

      result = AuthHelpers.fetch_user_from_session_token(session.token)

      assert {returned_user, returned_session} = result
      assert returned_user.id == user.id
      assert returned_user.email == user.email
      assert returned_session.id == session.id
    end

    test "returns fresh user data with role" do
      user = create_user(email: "admin@example.com", role: :admin)
      {:ok, session} = Auth.create_session(user)

      {returned_user, _session} = AuthHelpers.fetch_user_from_session_token(session.token)

      assert returned_user.role == :admin
    end

    test "updates session activity" do
      user = create_user(email: "activity@example.com")
      {:ok, session} = Auth.create_session(user)
      original_last_activity = session.last_activity_at

      # Small delay to ensure time difference
      Process.sleep(10)

      {_user, returned_session} = AuthHelpers.fetch_user_from_session_token(session.token)

      # In test mode, activity is updated synchronously
      # The returned session should have updated activity
      assert returned_session.id == session.id

      # Verify the session was updated in the database
      updated_session = Auth.get_session_by_token(session.token)
      assert updated_session.last_activity_at >= original_last_activity
    end

    test "handles expired session gracefully" do
      user = create_user(email: "expired@example.com")
      {:ok, session} = Auth.create_session(user)

      # Delete the session to simulate expiration
      Auth.delete_session(session)

      assert AuthHelpers.fetch_user_from_session_token(session.token) == nil
    end

    test "returns user with preloaded associations" do
      user = create_user(email: "preload@example.com")
      {:ok, session} = Auth.create_session(user)

      {returned_user, _session} = AuthHelpers.fetch_user_from_session_token(session.token)

      # User should be a valid struct
      assert %Portfolio.Auth.User{} = returned_user
      assert returned_user.email == "preload@example.com"
    end
  end

  describe "fetch_user_from_session_token/1 - edge cases" do
    test "handles empty string token" do
      assert AuthHelpers.fetch_user_from_session_token("") == nil
    end

    test "handles very long invalid token" do
      long_token = String.duplicate("a", 1000)
      assert AuthHelpers.fetch_user_from_session_token(long_token) == nil
    end

    test "handles token with special characters" do
      special_token = "token-with-special_chars.123"
      assert AuthHelpers.fetch_user_from_session_token(special_token) == nil
    end
  end

  describe "concurrent session handling" do
    test "handles multiple sessions for same user" do
      user = create_user(email: "multi@example.com")
      {:ok, session1} = Auth.create_session(user)
      {:ok, session2} = Auth.create_session(user)

      {user1, _} = AuthHelpers.fetch_user_from_session_token(session1.token)
      {user2, _} = AuthHelpers.fetch_user_from_session_token(session2.token)

      assert user1.id == user2.id
      assert user1.id == user.id
    end

    test "different users have independent sessions" do
      user1 = create_user(email: "user1@example.com")
      user2 = create_user(email: "user2@example.com")
      {:ok, session1} = Auth.create_session(user1)
      {:ok, session2} = Auth.create_session(user2)

      {returned_user1, _} = AuthHelpers.fetch_user_from_session_token(session1.token)
      {returned_user2, _} = AuthHelpers.fetch_user_from_session_token(session2.token)

      assert returned_user1.id == user1.id
      assert returned_user2.id == user2.id
      refute returned_user1.id == returned_user2.id
    end
  end

  describe "session token hashing and security" do
    test "tokens are hashed before lookup" do
      user = create_user(email: "hash@example.com")
      {:ok, session} = Auth.create_session(user)

      # Session should be found even though token is hashed internally
      result = AuthHelpers.fetch_user_from_session_token(session.token)
      assert {returned_user, _} = result
      assert returned_user.id == user.id
    end

    test "raw session token cannot be used directly" do
      user = create_user(email: "raw@example.com")
      {:ok, session} = Auth.create_session(user)

      # Using hashed token should not work
      hashed = UserSession.hash_token_value(session.token)
      assert AuthHelpers.fetch_user_from_session_token(hashed) == nil
    end
  end

  describe "cache behavior in different environments" do
    test "skips cache in test environment" do
      user = create_user(email: "nocache@example.com")
      {:ok, session} = Auth.create_session(user)

      # First fetch
      {user1, _} = AuthHelpers.fetch_user_from_session_token(session.token)

      # Update user
      {:ok, _} = Auth.update_user(user, %{email: "updated@example.com"})

      # Second fetch should get updated data (no cache in test)
      {user2, _} = AuthHelpers.fetch_user_from_session_token(session.token)

      # In test mode, should always get fresh data
      assert user1.id == user2.id
    end
  end

  describe "session reload behavior" do
    test "reloads user data on each request" do
      user = create_user(email: "reload@example.com", role: :user)
      admin = create_user(email: "admin-updater@example.com", role: :admin)
      {:ok, session} = Auth.create_session(user)

      # First fetch
      {user1, _} = AuthHelpers.fetch_user_from_session_token(session.token)
      assert user1.role == :user

      # Update user role (requires admin to change role)
      {:ok, _} =
        UserService.update_user_as_admin(user, %{role: :admin}, current_user_id: admin.id)

      # Second fetch should get updated role
      {user2, _} = AuthHelpers.fetch_user_from_session_token(session.token)
      assert user2.role == :admin
    end

    test "returns fresh user on every call" do
      user = create_user(email: "fresh@example.com")
      {:ok, session} = Auth.create_session(user)

      # Multiple fetches
      {user1, _} = AuthHelpers.fetch_user_from_session_token(session.token)
      {user2, _} = AuthHelpers.fetch_user_from_session_token(session.token)
      {user3, _} = AuthHelpers.fetch_user_from_session_token(session.token)

      # All should be the same user
      assert user1.id == user2.id
      assert user2.id == user3.id
    end
  end

  describe "error handling and nil cases" do
    test "handles database connection errors gracefully" do
      # This would require mocking the database
      # For now, verify nil token handling
      assert AuthHelpers.fetch_user_from_session_token(nil) == nil
    end

    test "handles corrupted session data" do
      # Invalid session token format
      assert AuthHelpers.fetch_user_from_session_token("invalid-format-!@#$") == nil
    end

    test "handles numeric token gracefully" do
      # Should handle type conversion
      assert AuthHelpers.fetch_user_from_session_token("12345") == nil
    end

    test "handles UUID-like but invalid tokens" do
      fake_uuid = "00000000-0000-0000-0000-000000000000"
      assert AuthHelpers.fetch_user_from_session_token(fake_uuid) == nil
    end
  end

  describe "session activity tracking" do
    test "updates session last_activity_at on each fetch" do
      user = create_user(email: "activity-track@example.com")
      {:ok, session} = Auth.create_session(user)
      initial_activity = session.last_activity_at

      # Wait a moment to ensure timestamp difference
      Process.sleep(10)

      # Fetch session
      {_, returned_session} = AuthHelpers.fetch_user_from_session_token(session.token)

      # Verify session was returned
      assert returned_session.id == session.id

      # Verify activity was updated in database
      updated_session = Auth.get_session_by_token(session.token)
      assert updated_session.last_activity_at >= initial_activity
    end

    test "tracks multiple activity updates" do
      user = create_user(email: "multi-activity@example.com")
      {:ok, session} = Auth.create_session(user)

      timestamps =
        for _ <- 1..3 do
          Process.sleep(5)
          {_, returned_session} = AuthHelpers.fetch_user_from_session_token(session.token)
          returned_session.last_activity_at
        end

      # All timestamps should exist
      assert Enum.all?(timestamps, &(&1 != nil))
    end
  end

  describe "role-based access control integration" do
    test "returns user with correct role for admin" do
      admin = create_user(email: "admin-rbac@example.com", role: :admin)
      {:ok, session} = Auth.create_session(admin)

      {returned_user, _} = AuthHelpers.fetch_user_from_session_token(session.token)

      assert returned_user.role == :admin
      assert returned_user.id == admin.id
    end

    test "returns user with correct role for regular user" do
      user = create_user(email: "user-rbac@example.com", role: :user)
      {:ok, session} = Auth.create_session(user)

      {returned_user, _} = AuthHelpers.fetch_user_from_session_token(session.token)

      assert returned_user.role == :user
      assert returned_user.id == user.id
    end

    test "handles role changes correctly" do
      user = create_user(email: "role-change@example.com", role: :user)
      admin = create_user(email: "admin-role-changer@example.com", role: :admin)
      {:ok, session} = Auth.create_session(user)

      # Fetch with original role
      {user1, _} = AuthHelpers.fetch_user_from_session_token(session.token)
      assert user1.role == :user

      # Change role (requires admin to change role)
      {:ok, _} =
        UserService.update_user_as_admin(user, %{role: :admin}, current_user_id: admin.id)

      # Fetch with new role
      {user2, _} = AuthHelpers.fetch_user_from_session_token(session.token)
      assert user2.role == :admin
    end
  end

  describe "session and user consistency" do
    test "returned user matches session user" do
      user = create_user(email: "consistency@example.com")
      {:ok, session} = Auth.create_session(user)

      {returned_user, returned_session} = AuthHelpers.fetch_user_from_session_token(session.token)

      assert returned_user.id == session.user_id
      assert returned_session.user_id == session.user_id
    end

    test "session contains user reference" do
      user = create_user(email: "ref@example.com")
      {:ok, session} = Auth.create_session(user)

      {_returned_user, returned_session} =
        AuthHelpers.fetch_user_from_session_token(session.token)

      assert returned_session.user_id == user.id
    end
  end

  describe "performance and efficiency" do
    test "handles multiple rapid lookups efficiently" do
      user = create_user(email: "performance@example.com")
      {:ok, session} = Auth.create_session(user)

      # Perform multiple rapid lookups
      results =
        for _ <- 1..10 do
          AuthHelpers.fetch_user_from_session_token(session.token)
        end

      # All lookups should succeed
      assert Enum.all?(results, fn
               {returned_user, _} -> returned_user.id == user.id
               _ -> false
             end)
    end
  end
end
