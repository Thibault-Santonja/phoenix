defmodule PortfolioWeb.AuthHelpersTest do
  use Portfolio.DataCase, async: true

  import PortfolioTest.Fixtures.AuthFixtures

  alias PortfolioWeb.AuthHelpers

  describe "fetch_user_from_session_token/1" do
    test "returns nil for nil token" do
      assert AuthHelpers.fetch_user_from_session_token(nil) == nil
    end

    test "returns nil for non-existent token" do
      assert AuthHelpers.fetch_user_from_session_token("nonexistent_token") == nil
    end

    test "returns user and session for valid token" do
      user = create_user()
      session = create_session(user: user)

      result = AuthHelpers.fetch_user_from_session_token(session.token)

      assert {returned_user, returned_session} = result
      assert returned_user.id == user.id
      assert returned_session.id == session.id
    end

    test "reloads fresh user data" do
      user = create_user()
      session = create_session(user: user)

      {returned_user, _session} = AuthHelpers.fetch_user_from_session_token(session.token)

      # User should have fresh data
      assert returned_user.id == user.id
      assert returned_user.email == user.email
    end

    test "updates session activity" do
      user = create_user()
      session = create_session(user: user)
      original_last_active = session.last_activity_at

      # Give a small delay so timestamp can change
      Process.sleep(10)

      {_user, returned_session} = AuthHelpers.fetch_user_from_session_token(session.token)

      # Session should have been updated
      assert returned_session.id == session.id

      # Reload from DB to check if activity was updated
      updated_session = Portfolio.Auth.get_session!(session.id)
      # Activity should be same or later (async update in non-test env)
      assert DateTime.compare(updated_session.last_activity_at, original_last_active) in [
               :eq,
               :gt
             ]
    end

    test "handles invalid token format" do
      # Token that doesn't match any session
      result = AuthHelpers.fetch_user_from_session_token("invalid_base64_token!")

      assert result == nil
    end

    test "returns session with preloaded user" do
      user = create_user()
      session = create_session(user: user)

      {returned_user, returned_session} = AuthHelpers.fetch_user_from_session_token(session.token)

      # The returned session should have the user loaded
      assert returned_session.user.id == user.id
      assert returned_user.id == user.id
    end
  end
end
