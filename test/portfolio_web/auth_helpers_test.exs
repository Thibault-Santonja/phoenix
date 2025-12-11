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
      assert AuthHelpers.fetch_user_from_session_token("invalid-token") == nil
    end

    test "returns nil for empty string token" do
      assert AuthHelpers.fetch_user_from_session_token("") == nil
    end

    test "returns {user, session} for valid token" do
      user = create_user()
      {:ok, session} = Auth.create_session(user)

      result = AuthHelpers.fetch_user_from_session_token(session.token)

      assert {returned_user, returned_session} = result
      assert returned_user.id == user.id
      assert returned_session.id == session.id
    end

    test "returns fresh user data with updated role" do
      user = create_user()
      {:ok, session} = Auth.create_session(user)

      # Promote user to admin using admin changeset
      {:ok, _updated_user} = Auth.update_user_as_admin(user, %{role: :admin})

      # Fetch should return fresh data
      {returned_user, _session} = AuthHelpers.fetch_user_from_session_token(session.token)

      assert returned_user.role == :admin
    end

    test "updates session activity" do
      user = create_user()
      {:ok, session} = Auth.create_session(user)

      original_activity = session.last_activity_at

      # Small delay to ensure time difference
      Process.sleep(10)

      {_user, updated_session} = AuthHelpers.fetch_user_from_session_token(session.token)

      # In test mode, activity is updated synchronously
      assert updated_session.id == session.id

      # Verify in database
      db_session = Auth.get_session_by_token(session.token)
      assert db_session.last_activity_at >= original_activity
    end

    test "returns nil for deleted session" do
      user = create_user()
      {:ok, session} = Auth.create_session(user)

      # Delete the session
      Auth.delete_session(session)

      result = AuthHelpers.fetch_user_from_session_token(session.token)

      assert result == nil
    end

    test "handles binary tokens correctly" do
      user = create_user()
      {:ok, session} = Auth.create_session(user)

      # Ensure the token is a binary string
      token = session.token
      assert is_binary(token)

      result = AuthHelpers.fetch_user_from_session_token(token)

      assert {_user, _session} = result
    end
  end
end
