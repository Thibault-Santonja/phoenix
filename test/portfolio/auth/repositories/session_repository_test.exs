defmodule Portfolio.Auth.Repositories.SessionRepositoryTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Auth.Repositories.SessionRepository
  alias Portfolio.Auth.UserSession

  import PortfolioTest.Fixtures.AuthFixtures

  # Helper to hash raw token for repository lookup
  defp hash_token(raw_token), do: UserSession.hash_token_value(raw_token)

  describe "get_by_token/2" do
    test "returns session when hashed token exists" do
      user = create_user()
      session = create_session(user: user)

      # session.token is raw, we need to hash it for lookup
      hashed_token = hash_token(session.token)
      assert {:ok, found} = SessionRepository.get_by_token(hashed_token)
      assert found.id == session.id
    end

    test "returns error when token does not exist" do
      assert {:error, :not_found} = SessionRepository.get_by_token("nonexistent_hashed_token")
    end

    test "preloads user when requested" do
      user = create_user()
      session = create_session(user: user)

      hashed_token = hash_token(session.token)
      assert {:ok, found} = SessionRepository.get_by_token(hashed_token, preload: [:user])
      assert found.user.id == user.id
      assert found.user.email == user.email
    end

    test "does not preload user by default" do
      user = create_user()
      session = create_session(user: user)

      hashed_token = hash_token(session.token)
      assert {:ok, found} = SessionRepository.get_by_token(hashed_token)
      assert %Ecto.Association.NotLoaded{} = found.user
    end
  end

  describe "get/1" do
    test "returns session when id exists" do
      user = create_user()
      session = create_session(user: user)

      assert {:ok, found} = SessionRepository.get(session.id)
      assert found.id == session.id
    end

    test "returns error when id does not exist" do
      assert {:error, :not_found} = SessionRepository.get(Ecto.UUID.generate())
    end
  end

  describe "get!/1" do
    test "returns session when id exists" do
      user = create_user()
      session = create_session(user: user)

      found = SessionRepository.get!(session.id)
      assert found.id == session.id
    end

    test "raises when id does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        SessionRepository.get!(Ecto.UUID.generate())
      end
    end
  end

  describe "reload_user/1" do
    test "reloads user association" do
      user = create_user()
      session = create_session(user: user)

      # Session without loaded user
      {:ok, session_without_user} = SessionRepository.get(session.id)
      assert %Ecto.Association.NotLoaded{} = session_without_user.user

      # Reload user
      reloaded = SessionRepository.reload_user(session_without_user)
      assert reloaded.user.id == user.id
    end
  end

  describe "list_by_user/2" do
    test "returns all sessions for user" do
      user = create_user()
      s1 = create_session(user: user)
      s2 = create_session(user: user)

      other_user = create_user()
      _other_session = create_session(user: other_user)

      sessions = SessionRepository.list_by_user(user.id)

      assert length(sessions) == 2
      ids = Enum.map(sessions, & &1.id)
      assert s1.id in ids
      assert s2.id in ids
    end

    test "returns empty list when user has no sessions" do
      user = create_user()

      assert [] = SessionRepository.list_by_user(user.id)
    end

    test "respects limit option" do
      user = create_user()

      for _ <- 1..5 do
        create_session(user: user)
      end

      sessions = SessionRepository.list_by_user(user.id, limit: 3)

      assert length(sessions) == 3
    end
  end

  describe "insert/1" do
    test "creates session with valid attrs" do
      user = create_user()
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

      attrs = %{
        user_id: user.id,
        token: token,
        last_activity_at: now
      }

      assert {:ok, session} = SessionRepository.insert(attrs)
      assert session.user_id == user.id
      # Token should be hashed
      assert session.token != token
    end

    test "returns error with invalid attrs" do
      assert {:error, changeset} = SessionRepository.insert(%{})
      refute changeset.valid?
    end
  end

  describe "update_activity/2" do
    test "updates last_activity_at timestamp" do
      user = create_user()
      session = create_session(user: user)
      original_activity = session.last_activity_at

      new_time =
        DateTime.utc_now()
        |> DateTime.add(3600)
        |> DateTime.truncate(:second)

      assert {:ok, updated} = SessionRepository.update_activity(session, new_time)
      assert updated.last_activity_at == new_time
      assert updated.last_activity_at != original_activity
    end
  end

  describe "update/2" do
    test "updates session attributes" do
      user = create_user()
      session = create_session(user: user)

      new_time =
        DateTime.utc_now()
        |> DateTime.add(7200)
        |> DateTime.truncate(:second)

      assert {:ok, updated} = SessionRepository.update(session, %{last_activity_at: new_time})
      assert updated.last_activity_at == new_time
    end
  end

  describe "delete/1" do
    test "deletes the session" do
      user = create_user()
      session = create_session(user: user)

      assert {:ok, deleted} = SessionRepository.delete(session)
      assert deleted.id == session.id

      assert {:error, :not_found} = SessionRepository.get(session.id)
    end
  end

  describe "delete_all_for_user/1" do
    test "deletes all sessions for specific user" do
      user1 = create_user()
      user2 = create_user()

      create_session(user: user1)
      create_session(user: user1)
      s_user2 = create_session(user: user2)

      {count, _} = SessionRepository.delete_all_for_user(user1.id)

      assert count == 2
      assert [] = SessionRepository.list_by_user(user1.id)
      assert {:ok, _} = SessionRepository.get(s_user2.id)
    end
  end

  describe "delete_all_for_user_except/2" do
    test "deletes all sessions except specified one" do
      user = create_user()
      current = create_session(user: user)
      _other1 = create_session(user: user)
      _other2 = create_session(user: user)

      {count, _} = SessionRepository.delete_all_for_user_except(user.id, current.id)

      assert count == 2
      sessions = SessionRepository.list_by_user(user.id)
      assert length(sessions) == 1
      assert hd(sessions).id == current.id
    end
  end

  describe "delete_expired/1" do
    test "deletes sessions older than expiry period" do
      user = create_user()
      expiry_seconds = 3600

      # Create an old session by manipulating the timestamp
      old_time =
        DateTime.utc_now()
        |> DateTime.add(-7200)
        |> DateTime.truncate(:second)

      old_session = create_session(user: user)
      SessionRepository.update(old_session, %{last_activity_at: old_time})

      recent_session = create_session(user: user)

      {count, _} = SessionRepository.delete_expired(expiry_seconds)

      assert count >= 1
      assert {:error, :not_found} = SessionRepository.get(old_session.id)
      assert {:ok, _} = SessionRepository.get(recent_session.id)
    end
  end

  describe "count_active/1" do
    test "counts sessions with recent activity" do
      user = create_user()
      expiry_seconds = 3600

      # Create recent session
      _recent = create_session(user: user)

      # Create old session
      old_time =
        DateTime.utc_now()
        |> DateTime.add(-7200)
        |> DateTime.truncate(:second)

      old_session = create_session(user: user)
      SessionRepository.update(old_session, %{last_activity_at: old_time})

      count = SessionRepository.count_active(expiry_seconds)

      # Should count at least the recent session
      assert count >= 1
    end
  end

  describe "count/0" do
    test "counts total sessions" do
      user = create_user()
      initial_count = SessionRepository.count()

      create_session(user: user)
      create_session(user: user)

      assert SessionRepository.count() == initial_count + 2
    end
  end

  describe "count_for_user/1" do
    test "counts sessions for specific user" do
      user1 = create_user()
      user2 = create_user()

      create_session(user: user1)
      create_session(user: user1)
      create_session(user: user2)

      assert SessionRepository.count_for_user(user1.id) == 2
      assert SessionRepository.count_for_user(user2.id) == 1
    end

    test "returns 0 for user with no sessions" do
      user = create_user()

      assert SessionRepository.count_for_user(user.id) == 0
    end
  end
end
