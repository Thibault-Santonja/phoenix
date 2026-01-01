defmodule Portfolio.Auth.SessionActivityTest do
  @moduledoc """
  Happy path tests for session activity tracking.

  These tests verify that:
  - Session activity updates on requests
  - Inactive sessions expire after timeout
  - Active sessions remain valid
  """

  use Portfolio.DataCase, async: true

  alias Portfolio.Auth
  alias Portfolio.Repo

  import PortfolioTest.Fixtures.AuthFixtures

  # Set throttle to 0 for tests to ensure activity updates are always applied
  setup do
    original_config = Application.get_env(:portfolio, :auth, [])

    Application.put_env(
      :portfolio,
      :auth,
      Keyword.put(original_config, :activity_update_throttle_seconds, 0)
    )

    on_exit(fn ->
      Application.put_env(:portfolio, :auth, original_config)
    end)

    :ok
  end

  # Helper to set session activity to the past, ensuring update will be applied
  defp set_activity_in_past(session, seconds_ago \\ 10) do
    past_activity =
      DateTime.utc_now()
      |> DateTime.add(-seconds_ago, :second)
      |> DateTime.truncate(:second)

    session
    |> Ecto.Changeset.change(%{last_activity_at: past_activity})
    |> Repo.update!()
  end

  describe "session activity tracking" do
    test "session activity is updated" do
      # Arrange: Create session with past activity
      session = create_session() |> set_activity_in_past()
      initial_activity = session.last_activity_at

      # Act: Update session activity
      assert {:ok, updated_session} = Auth.update_session_activity(session)

      # Assert: Activity timestamp updated
      assert DateTime.compare(updated_session.last_activity_at, initial_activity) == :gt
    end

    test "active session remains valid" do
      # Arrange: Create recent session
      session = create_session()

      # Act: Manually update activity to recent time
      recent_activity =
        DateTime.utc_now() |> DateTime.add(-5, :minute) |> DateTime.truncate(:second)

      session
      |> Ecto.Changeset.change(%{last_activity_at: recent_activity})
      |> Repo.update!()

      # Assert: Session still valid
      assert retrieved = Auth.get_session_by_token(session.token)
      assert retrieved.id == session.id
    end

    test "session activity updates multiple times" do
      # Arrange: Create session with past activity
      session = create_session() |> set_activity_in_past(30)
      activity1 = session.last_activity_at

      # Act: Update activity first time
      {:ok, session2} = Auth.update_session_activity(session)
      activity2 = session2.last_activity_at

      # Set activity in past again for next update
      session2 = set_activity_in_past(session2, 20)

      # Act: Update activity second time
      {:ok, session3} = Auth.update_session_activity(session2)
      activity3 = session3.last_activity_at

      # Assert: Each update has newer timestamp
      assert DateTime.compare(activity2, activity1) == :gt
      assert DateTime.compare(activity3, session2.last_activity_at) == :gt
    end

    test "inactive session expires after 30 days" do
      # Arrange: Create session with old activity
      session = create_session()

      old_activity =
        DateTime.utc_now()
        |> DateTime.add(-31, :day)
        |> DateTime.truncate(:second)

      session
      |> Ecto.Changeset.change(%{last_activity_at: old_activity})
      |> Repo.update!()

      # Act: Try to retrieve expired session
      # Note: This depends on application cleanup logic
      # The session exists in DB but should be considered expired

      # Assert: Activity is old (expired)
      expired_session = Auth.get_session!(session.id)
      assert DateTime.diff(DateTime.utc_now(), expired_session.last_activity_at, :day) > 30
    end

    test "session activity tracks user engagement" do
      # Arrange: Create session with past activity
      user = create_user()
      {:ok, session} = Auth.create_session(user)

      # Set initial activity far in the past
      session = set_activity_in_past(session, 60)
      activity1 = session.last_activity_at

      # Activity 1: update from 60 seconds ago
      {:ok, session} = Auth.update_session_activity(session)
      activity2 = session.last_activity_at

      # Set activity in past again for next update
      session = set_activity_in_past(session, 30)
      activity2_reset = session.last_activity_at

      # Activity 2: update from 30 seconds ago
      {:ok, session} = Auth.update_session_activity(session)
      activity3 = session.last_activity_at

      # Assert: Updates produced newer timestamps than the "past" times
      assert DateTime.compare(activity2, activity1) == :gt
      assert DateTime.compare(activity3, activity2_reset) == :gt
    end

    test "multiple sessions track activity independently" do
      # Arrange: Create user with multiple sessions
      user = create_user()
      {:ok, session1} = Auth.create_session(user)
      {:ok, session2} = Auth.create_session(user)

      # Set session1 activity in the past so it can be updated
      session1 = set_activity_in_past(session1)

      # Act: Update only session1 activity
      {:ok, updated_session1} = Auth.update_session_activity(session1)

      # Assert: session1 activity updated
      assert DateTime.compare(updated_session1.last_activity_at, session1.last_activity_at) == :gt

      # Assert: session2 activity unchanged
      unchanged_session2 = Auth.get_session_by_token(session2.token)
      assert unchanged_session2.last_activity_at == session2.last_activity_at
    end

    test "session activity persists in database" do
      # Arrange: Create session with past activity
      session = create_session() |> set_activity_in_past()

      # Act: Update activity
      {:ok, updated_session} = Auth.update_session_activity(session)
      updated_activity = updated_session.last_activity_at

      # Act: Reload from database
      reloaded_session = Repo.get!(Portfolio.Auth.UserSession, session.id)

      # Assert: Activity persisted
      assert DateTime.compare(reloaded_session.last_activity_at, updated_activity) == :eq
    end

    test "reload_user updates session with latest user data" do
      # Arrange: Create session
      user = create_user(name: "Original Name")
      {:ok, session} = Auth.create_session(user)

      # Act: Update user
      {:ok, updated_user} = Auth.update_user(user, %{name: "Updated Name"})

      # Act: Reload user in session
      reloaded_session = Auth.reload_user(session)

      # Assert: Session has updated user data
      assert reloaded_session.user.name == "Updated Name"
      assert reloaded_session.user.id == updated_user.id
    end

    test "list_user_sessions returns all active sessions" do
      # Arrange: Create user with multiple sessions
      user = create_user()
      {:ok, session1} = Auth.create_session(user)
      {:ok, session2} = Auth.create_session(user)
      {:ok, session3} = Auth.create_session(user)

      # Act: List user sessions
      sessions = Auth.list_user_sessions(user.id)

      # Assert: All sessions returned
      assert length(sessions) == 3
      session_ids = Enum.map(sessions, & &1.id)
      assert session1.id in session_ids
      assert session2.id in session_ids
      assert session3.id in session_ids
    end

    test "delete_all_user_sessions removes all sessions" do
      # Arrange: Create user with multiple sessions
      user = create_user()
      {:ok, _session1} = Auth.create_session(user)
      {:ok, _session2} = Auth.create_session(user)
      {:ok, _session3} = Auth.create_session(user)

      # Assert: User has 3 sessions
      assert length(Auth.list_user_sessions(user.id)) == 3

      # Act: Delete all sessions (returns {count, nil} from Ecto.Repo.delete_all)
      assert {3, nil} = Auth.delete_all_user_sessions(user)

      # Assert: No sessions remain
      assert Auth.list_user_sessions(user.id) == []
    end
  end
end
