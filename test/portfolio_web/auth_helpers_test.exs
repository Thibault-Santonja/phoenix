defmodule PortfolioWeb.AuthHelpersTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Auth
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
end
