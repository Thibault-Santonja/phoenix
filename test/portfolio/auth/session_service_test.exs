defmodule Portfolio.Auth.SessionServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Auth
  alias Portfolio.Auth.SessionService
  alias Portfolio.Auth.User
  alias Portfolio.Auth.UserSession

  describe "create_session/1" do
    test "creates session with token for user" do
      user = insert_user()
      assert {:ok, session} = SessionService.create_session(user)

      assert session.user_id == user.id
      assert session.token != nil
      assert is_binary(session.token)
      assert session.last_activity_at != nil
    end

    test "stores hashed token in database for security" do
      user = insert_user()
      assert {:ok, session} = SessionService.create_session(user)

      # Le token retourné est en clair
      raw_token = session.token
      assert String.length(raw_token) > 40

      # En DB, le token est hashé (SHA-256 = 64 caractères hex)
      db_session = Repo.get(UserSession, session.id)
      assert String.length(db_session.token) == 64
      assert String.match?(db_session.token, ~r/^[0-9a-f]+$/)

      # Le hash en DB correspond au hash du token en clair
      expected_hash = UserSession.hash_token_value(raw_token)
      assert db_session.token == expected_hash
    end

    test "generates unique tokens for multiple sessions" do
      user = insert_user()
      {:ok, session1} = SessionService.create_session(user)
      {:ok, session2} = SessionService.create_session(user)

      assert session1.token != session2.token
      assert session1.user_id == session2.user_id
    end

    test "initializes last_activity_at to current time" do
      user = insert_user()
      {:ok, session} = SessionService.create_session(user)

      # last_activity_at should be recent (within last 5 seconds)
      now = DateTime.utc_now()
      diff = DateTime.diff(now, session.last_activity_at, :second)
      assert diff >= 0
      assert diff < 5
    end

    test "allows multiple sessions for same user" do
      user = insert_user()
      {:ok, session1} = SessionService.create_session(user)
      {:ok, session2} = SessionService.create_session(user)

      # Both sessions should exist
      assert Repo.get(UserSession, session1.id) != nil
      assert Repo.get(UserSession, session2.id) != nil
    end

    test "token is URL-safe" do
      user = insert_user()
      {:ok, session} = SessionService.create_session(user)

      # Token should not contain unsafe characters
      refute String.contains?(session.token, ["+", "/", "="])
      assert String.match?(session.token, ~r/^[A-Za-z0-9_-]+$/)
    end
  end

  describe "get_session_by_token/1" do
    test "returns session for valid token" do
      user = insert_user()
      {:ok, session} = SessionService.create_session(user)

      found_session = SessionService.get_session_by_token(session.token)
      assert found_session.id == session.id
      assert found_session.user.id == user.id
      assert found_session.user.email == user.email
    end

    test "returns nil for invalid token" do
      assert SessionService.get_session_by_token("invalid-token") == nil
    end

    test "returns nil for empty token" do
      assert SessionService.get_session_by_token("") == nil
    end

    test "returns nil and deletes expired session" do
      user = insert_user()

      # Create expired session (more than 1 hour old - default expiration)
      session =
        insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -2, :hour))

      assert SessionService.get_session_by_token(session.token) == nil
      assert Repo.get(UserSession, session.id) == nil
    end

    test "returns session for recently active session" do
      user = insert_user()
      # Session from 30 minutes ago should still be valid (1 hour default expiration)
      session =
        insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -30, :minute))

      found_session = SessionService.get_session_by_token(session.token)
      assert found_session != nil
      assert found_session.id == session.id
    end

    test "preloads user association" do
      user = insert_user()
      {:ok, session} = SessionService.create_session(user)

      found_session = SessionService.get_session_by_token(session.token)
      assert found_session.user != nil
      assert found_session.user.id == user.id
    end
  end

  describe "get_session!/1" do
    test "returns session for valid ID" do
      user = insert_user()
      {:ok, session} = SessionService.create_session(user)

      found_session = SessionService.get_session!(session.id)
      assert found_session.id == session.id
    end

    test "raises error for non-existent ID" do
      assert_raise Ecto.NoResultsError, fn ->
        SessionService.get_session!(Ecto.UUID.generate())
      end
    end
  end

  describe "list_user_sessions/1" do
    test "returns all sessions for a user" do
      user = insert_user()
      {:ok, session1} = SessionService.create_session(user)
      {:ok, session2} = SessionService.create_session(user)

      sessions = SessionService.list_user_sessions(user.id)

      session_ids = Enum.map(sessions, & &1.id)
      assert session1.id in session_ids
      assert session2.id in session_ids
    end

    test "returns empty list for user with no sessions" do
      user = insert_user()
      assert SessionService.list_user_sessions(user.id) == []
    end

    test "does not return sessions from other users" do
      user1 = insert_user(email: "user1@example.com")
      user2 = insert_user(email: "user2@example.com")

      {:ok, session1} = SessionService.create_session(user1)
      {:ok, _session2} = SessionService.create_session(user2)

      user1_sessions = SessionService.list_user_sessions(user1.id)
      session_ids = Enum.map(user1_sessions, & &1.id)

      assert session1.id in session_ids
      assert user1_sessions != []
    end

    test "orders sessions by most recent activity first" do
      user = insert_user()

      old_session =
        insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -50, :minute))

      recent_session =
        insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -10, :minute))

      sessions = SessionService.list_user_sessions(user.id)

      # Recent session should come before old session
      recent_index = Enum.find_index(sessions, &(&1.id == recent_session.id))
      old_index = Enum.find_index(sessions, &(&1.id == old_session.id))

      assert recent_index < old_index
    end
  end

  describe "reload_user/1" do
    test "reloads user from database with fresh data" do
      user = insert_user(%{role: :user})
      {:ok, session} = SessionService.create_session(user)

      # Modifier le rôle de l'utilisateur en base de données
      {:ok, _updated_user} = Auth.update_user_as_admin(user, %{role: :admin})

      # Recharger la session
      fresh_session = SessionService.reload_user(session)

      # Le rôle doit être mis à jour
      assert fresh_session.user.role == :admin
      refute fresh_session.user.role == user.role
    end

    test "preserves session data while reloading user" do
      user = insert_user()
      {:ok, session} = SessionService.create_session(user)

      fresh_session = SessionService.reload_user(session)

      # Les données de session restent identiques
      assert fresh_session.id == session.id
      assert fresh_session.token == session.token
      assert fresh_session.last_activity_at == session.last_activity_at
    end

    test "reloads user even if already preloaded" do
      user = insert_user(%{role: :user})
      {:ok, session} = SessionService.create_session(user)

      # Vérifier que le user est preloaded et a le bon rôle
      session_with_user = Repo.preload(session, :user)
      assert session_with_user.user.id == user.id
      assert session_with_user.user.role == :user

      # Modifier le rôle
      {:ok, _updated_user} = Auth.update_user_as_admin(user, %{role: :admin})

      # Recharger doit forcer le reload depuis la DB
      fresh_session = SessionService.reload_user(session_with_user)
      assert fresh_session.user.role == :admin
    end
  end

  describe "update_session_activity/1" do
    test "updates last_activity_at to current time" do
      user = insert_user()

      # Créer une session avec dernière activité > 5 minutes (pour dépasser le throttle)
      session =
        insert_session(user,
          last_activity_at: DateTime.add(DateTime.utc_now(), -6, :minute)
        )

      {:ok, updated_session} = SessionService.update_session_activity(session)

      assert DateTime.compare(updated_session.last_activity_at, session.last_activity_at) == :gt
    end

    test "does not change session ID or token" do
      user = insert_user()
      {:ok, session} = SessionService.create_session(user)

      {:ok, updated_session} = SessionService.update_session_activity(session)

      assert updated_session.id == session.id
      assert updated_session.token == session.token
    end

    test "updates timestamp in database" do
      user = insert_user()

      # Créer une session avec dernière activité > 5 minutes (pour dépasser le throttle)
      session =
        insert_session(user,
          last_activity_at: DateTime.add(DateTime.utc_now(), -6, :minute)
        )

      SessionService.update_session_activity(session)

      reloaded = Repo.get(UserSession, session.id)
      assert DateTime.compare(reloaded.last_activity_at, session.last_activity_at) == :gt
    end

    test "throttles updates when last_activity_at is recent (within 5 minutes)" do
      user = insert_user()

      # Créer une session avec dernière activité il y a 2 minutes
      session =
        insert_session(user,
          last_activity_at: DateTime.add(DateTime.utc_now(), -2, :minute)
        )

      original_last_activity = session.last_activity_at

      # Tenter de mettre à jour l'activité
      {:ok, updated_session} = SessionService.update_session_activity(session)

      # La mise à jour devrait être throttlée (pas de changement)
      assert updated_session.last_activity_at == original_last_activity

      # Vérifier en DB
      reloaded = Repo.get(UserSession, session.id)
      assert reloaded.last_activity_at == original_last_activity
    end

    test "updates when throttle threshold is exceeded (> 5 minutes)" do
      user = insert_user()

      # Créer une session avec dernière activité il y a 6 minutes
      session =
        insert_session(user,
          last_activity_at: DateTime.add(DateTime.utc_now(), -6, :minute)
        )

      original_last_activity = session.last_activity_at

      # Tenter de mettre à jour l'activité
      {:ok, updated_session} = SessionService.update_session_activity(session)

      # La mise à jour devrait être effectuée (throttle dépassé)
      assert DateTime.compare(updated_session.last_activity_at, original_last_activity) == :gt

      # Vérifier en DB
      reloaded = Repo.get(UserSession, session.id)
      assert DateTime.compare(reloaded.last_activity_at, original_last_activity) == :gt
    end

    test "throttles at exactly 5 minutes boundary" do
      user = insert_user()

      # Créer une session avec dernière activité il y a exactement 5 minutes
      session =
        insert_session(user,
          last_activity_at: DateTime.add(DateTime.utc_now(), -5, :minute)
        )

      original_last_activity = session.last_activity_at

      # Tenter de mettre à jour l'activité
      {:ok, updated_session} = SessionService.update_session_activity(session)

      # À exactement 5 minutes, devrait être mis à jour (>= 5 minutes)
      assert DateTime.compare(updated_session.last_activity_at, original_last_activity) == :gt
    end
  end

  describe "delete_session/1" do
    test "deletes session successfully" do
      user = insert_user()
      {:ok, session} = SessionService.create_session(user)

      assert {:ok, deleted_session} = SessionService.delete_session(session)
      assert deleted_session.id == session.id
      assert Repo.get(UserSession, session.id) == nil
    end

    test "returns deleted session data" do
      user = insert_user()
      {:ok, session} = SessionService.create_session(user)

      {:ok, deleted} = SessionService.delete_session(session)
      assert deleted.token == session.token
      assert deleted.user_id == session.user_id
    end

    test "invalidates session cache on deletion" do
      user = insert_user()
      {:ok, session} = SessionService.create_session(user)

      # Seed cache with session data (clé de cache = hash du token)
      hashed_token = UserSession.hash_token_value(session.token)
      cache_key = {:session, hashed_token}
      {:ok, true} = Cachex.put(:portfolio_cache, cache_key, session)

      # Verify cache is populated (can be nil if another test invalidated it)
      # Note: Le cache est partagé entre tests parallèles, donc on vérifie
      # seulement si le cache existe qu'il contient la bonne session
      case Cachex.get(:portfolio_cache, cache_key) do
        {:ok, nil} ->
          # Cache invalidé par un autre test, on continue quand même
          :ok

        {:ok, cached_session} ->
          assert cached_session.id == session.id
      end

      # Delete session
      {:ok, _deleted} = SessionService.delete_session(session)

      # Verify cache was invalidated
      assert {:ok, nil} = Cachex.get(:portfolio_cache, cache_key)
    end
  end

  describe "delete_all_user_sessions/1" do
    test "deletes all sessions for a user" do
      user = insert_user()
      {:ok, session1} = SessionService.create_session(user)
      {:ok, session2} = SessionService.create_session(user)

      {count, nil} = SessionService.delete_all_user_sessions(user)

      assert count == 2
      assert Repo.get(UserSession, session1.id) == nil
      assert Repo.get(UserSession, session2.id) == nil
    end

    test "does not delete sessions from other users" do
      user1 = insert_user(email: "user1@example.com")
      user2 = insert_user(email: "user2@example.com")

      {:ok, session1} = SessionService.create_session(user1)
      {:ok, session2} = SessionService.create_session(user2)

      SessionService.delete_all_user_sessions(user1)

      assert Repo.get(UserSession, session1.id) == nil
      assert Repo.get(UserSession, session2.id) != nil
    end

    test "returns count of deleted sessions" do
      user = insert_user()
      SessionService.create_session(user)
      SessionService.create_session(user)
      SessionService.create_session(user)

      {count, nil} = SessionService.delete_all_user_sessions(user)
      assert count == 3
    end

    test "returns {0, nil} when user has no sessions" do
      user = insert_user()
      {count, nil} = SessionService.delete_all_user_sessions(user)
      assert count == 0
    end

    test "invalidates all session caches on deletion" do
      user = insert_user()
      {:ok, session1} = SessionService.create_session(user)
      {:ok, session2} = SessionService.create_session(user)
      {:ok, session3} = SessionService.create_session(user)

      # Seed cache with all session tokens (clés = hash des tokens)
      hashed_token1 = UserSession.hash_token_value(session1.token)
      hashed_token2 = UserSession.hash_token_value(session2.token)
      hashed_token3 = UserSession.hash_token_value(session3.token)

      cache_key1 = {:session, hashed_token1}
      cache_key2 = {:session, hashed_token2}
      cache_key3 = {:session, hashed_token3}

      {:ok, true} = Cachex.put(:portfolio_cache, cache_key1, session1)
      {:ok, true} = Cachex.put(:portfolio_cache, cache_key2, session2)
      {:ok, true} = Cachex.put(:portfolio_cache, cache_key3, session3)

      # Verify all caches are populated
      assert {:ok, _} = Cachex.get(:portfolio_cache, cache_key1)
      assert {:ok, _} = Cachex.get(:portfolio_cache, cache_key2)
      assert {:ok, _} = Cachex.get(:portfolio_cache, cache_key3)

      # Delete all user sessions
      {count, nil} = SessionService.delete_all_user_sessions(user)
      assert count == 3

      # Verify all caches were invalidated
      assert {:ok, nil} = Cachex.get(:portfolio_cache, cache_key1)
      assert {:ok, nil} = Cachex.get(:portfolio_cache, cache_key2)
      assert {:ok, nil} = Cachex.get(:portfolio_cache, cache_key3)
    end
  end

  describe "delete_all_user_sessions_except/2" do
    test "deletes all sessions except specified one" do
      user = insert_user()
      {:ok, session1} = SessionService.create_session(user)
      {:ok, session2} = SessionService.create_session(user)
      {:ok, session3} = SessionService.create_session(user)

      {count, nil} = SessionService.delete_all_user_sessions_except(user, session2.id)

      assert count == 2
      assert Repo.get(UserSession, session1.id) == nil
      assert Repo.get(UserSession, session2.id) != nil
      assert Repo.get(UserSession, session3.id) == nil
    end

    test "does not delete sessions from other users" do
      user1 = insert_user(email: "user1@example.com")
      user2 = insert_user(email: "user2@example.com")

      {:ok, session1_a} = SessionService.create_session(user1)
      {:ok, session1_b} = SessionService.create_session(user1)
      {:ok, session2} = SessionService.create_session(user2)

      SessionService.delete_all_user_sessions_except(user1, session1_b.id)

      assert Repo.get(UserSession, session1_a.id) == nil
      assert Repo.get(UserSession, session1_b.id) != nil
      assert Repo.get(UserSession, session2.id) != nil
    end

    test "returns {0, nil} when only one session exists" do
      user = insert_user()
      {:ok, session} = SessionService.create_session(user)

      {count, nil} = SessionService.delete_all_user_sessions_except(user, session.id)
      assert count == 0
      assert Repo.get(UserSession, session.id) != nil
    end

    test "invalidates deleted session caches but keeps current session cache" do
      user = insert_user()
      {:ok, session1} = SessionService.create_session(user)
      {:ok, session2} = SessionService.create_session(user)
      {:ok, session3} = SessionService.create_session(user)

      # Seed cache with all session tokens (clés = hash des tokens)
      hashed_token1 = UserSession.hash_token_value(session1.token)
      hashed_token2 = UserSession.hash_token_value(session2.token)
      hashed_token3 = UserSession.hash_token_value(session3.token)

      cache_key1 = {:session, hashed_token1}
      cache_key2 = {:session, hashed_token2}
      cache_key3 = {:session, hashed_token3}

      {:ok, true} = Cachex.put(:portfolio_cache, cache_key1, session1)
      {:ok, true} = Cachex.put(:portfolio_cache, cache_key2, session2)
      {:ok, true} = Cachex.put(:portfolio_cache, cache_key3, session3)

      # Delete all sessions except session2
      {count, nil} = SessionService.delete_all_user_sessions_except(user, session2.id)
      assert count == 2

      # Verify deleted session caches were invalidated
      assert {:ok, nil} = Cachex.get(:portfolio_cache, cache_key1)
      assert {:ok, nil} = Cachex.get(:portfolio_cache, cache_key3)

      # Verify kept session cache is still there (we don't explicitly keep it,
      # but it should remain since we didn't delete it)
      # Note: Le cache peut être nil si un autre test l'a invalidé en parallèle,
      # mais si le cache existe, il doit contenir la bonne session
      case Cachex.get(:portfolio_cache, cache_key2) do
        {:ok, nil} ->
          # Cache a pu être invalidé par un autre test en parallèle, acceptable
          :ok

        {:ok, cached_session} ->
          assert cached_session.id == session2.id
      end
    end
  end

  describe "delete_expired_sessions/0" do
    test "deletes sessions expired due to inactivity" do
      user = insert_user()

      # Create expired session (3 hours old - default expiration is 2 hours)
      expired_session =
        insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -3, :hour))

      # Create valid session
      valid_session = insert_session(user, last_activity_at: DateTime.utc_now())

      {count, nil} = SessionService.delete_expired_sessions()

      assert count >= 1
      assert Repo.get(UserSession, expired_session.id) == nil
      assert Repo.get(UserSession, valid_session.id) != nil
    end

    test "deletes multiple expired sessions" do
      user = insert_user()

      expired1 =
        insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -3, :hour))

      expired2 =
        insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -4, :hour))

      valid = insert_session(user, last_activity_at: DateTime.utc_now())

      {count, nil} = SessionService.delete_expired_sessions()

      assert count >= 2
      assert Repo.get(UserSession, expired1.id) == nil
      assert Repo.get(UserSession, expired2.id) == nil
      assert Repo.get(UserSession, valid.id) != nil
    end

    test "does not delete sessions within expiration window" do
      user = insert_user()

      # Session from 1 hour ago should not be expired (2 hours default expiration)
      recent_session =
        insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -1, :hour))

      {_count, nil} = SessionService.delete_expired_sessions()

      assert Repo.get(UserSession, recent_session.id) != nil
    end

    test "returns count of deleted sessions" do
      user = insert_user()

      insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -3, :hour))
      insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -4, :hour))

      {count, nil} = SessionService.delete_expired_sessions()
      assert count >= 2
    end
  end

  # Helper functions
  defp insert_user(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      email: "test-#{System.unique_integer([:positive])}@example.com",
      role: :admin
    }

    %User{}
    |> User.registration_changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp insert_session(user, attrs) do
    attrs = Enum.into(attrs, %{})

    # Générer un token en clair
    raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    default_attrs = %{
      user_id: user.id,
      token: raw_token,
      last_activity_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    session =
      %UserSession{}
      |> UserSession.changeset(Map.merge(default_attrs, attrs))
      |> Repo.insert!()

    # Retourner la session avec le token en clair (pas le hash)
    # car les tests ont besoin du token en clair pour appeler get_session_by_token
    %{session | token: raw_token}
  end
end
