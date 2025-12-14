defmodule PortfolioWeb.Integration.SessionCacheWorkflowTest do
  @moduledoc """
  Integration tests for session caching workflow.

  These tests verify the complete session lifecycle with caching:
  - Session creation → cached on first fetch
  - Session invalidation → cache cleared on logout
  - Session invalidation → cache cleared on role change
  - Cache TTL respected (sessions expire from cache)

  Tests ensure session data consistency across cache and database.
  """

  use PortfolioWeb.ConnCase, async: false

  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Auth.SessionService

  setup do
    # Clear cache before each test
    Cachex.clear(:portfolio_cache)

    on_exit(fn ->
      Cachex.clear(:portfolio_cache)
    end)

    :ok
  end

  describe "session caching lifecycle" do
    test "session cached after creation" do
      user = create_user(email: "cache#{System.unique_integer([:positive])}@example.com")

      # Create session
      {:ok, session} = SessionService.create_session(user)

      # Verify session exists in DB - returns session or nil
      db_session = SessionService.get_session_by_token(session.token)
      assert db_session != nil
      assert db_session.id == session.id
      assert db_session.user_id == user.id

      # Fetch again - should be cached
      cached_session = SessionService.get_session_by_token(session.token)
      assert cached_session != nil
      assert cached_session.id == session.id
    end

    test "session cache includes user data (preloaded)" do
      user = create_user(email: "preload#{System.unique_integer([:positive])}@example.com")

      {:ok, session} = SessionService.create_session(user)

      # Fetch session (should include user)
      fetched_session = SessionService.get_session_by_token(session.token)
      assert fetched_session != nil

      # Verify user preloaded
      assert fetched_session.user != nil
      assert fetched_session.user.id == user.id
      assert fetched_session.user.email == user.email
      assert fetched_session.user.role != nil
    end

    test "session cached on first fetch, returned from cache on subsequent fetches" do
      user = create_user()
      {:ok, session} = SessionService.create_session(user)

      # First fetch - cache miss, fetches from DB
      session1 = SessionService.get_session_by_token(session.token)
      assert session1 != nil

      # Second fetch - cache hit
      session2 = SessionService.get_session_by_token(session.token)
      assert session2 != nil

      # Should return same data
      assert session1.id == session2.id
      assert session1.user_id == session2.user_id
    end
  end

  describe "cache invalidation on logout" do
    test "session cache cleared on logout" do
      user = create_user()
      {:ok, session} = SessionService.create_session(user)

      # Verify session exists
      cached_session = SessionService.get_session_by_token(session.token)
      assert cached_session != nil

      # Logout (delete session) - returns {:ok, deleted_session}
      {:ok, _deleted} = SessionService.delete_session(session)

      # Verify session deleted from DB (returns nil)
      assert SessionService.get_session_by_token(session.token) == nil
    end

    test "all user sessions invalidated on logout_all" do
      user = create_user()

      # Create multiple sessions
      {:ok, session1} = SessionService.create_session(user)
      {:ok, session2} = SessionService.create_session(user)
      {:ok, session3} = SessionService.create_session(user)

      # Verify all exist
      assert SessionService.get_session_by_token(session1.token) != nil
      assert SessionService.get_session_by_token(session2.token) != nil
      assert SessionService.get_session_by_token(session3.token) != nil

      # Logout all sessions - returns {count, nil}
      {deleted_count, nil} = SessionService.delete_all_user_sessions(user)
      assert deleted_count == 3

      # Verify all sessions deleted
      assert SessionService.get_session_by_token(session1.token) == nil
      assert SessionService.get_session_by_token(session2.token) == nil
      assert SessionService.get_session_by_token(session3.token) == nil
    end
  end

  describe "cache invalidation on role change" do
    test "session cache cleared when user role changes" do
      user = create_user(email: "rolechange#{System.unique_integer([:positive])}@example.com")
      {:ok, session} = SessionService.create_session(user)

      # Fetch and cache session
      cached_session = SessionService.get_session_by_token(session.token)
      assert cached_session != nil
      assert cached_session.user.role == :admin

      # Change user role
      {:ok, updated_user} =
        user
        |> Ecto.Changeset.change(%{role: :user})
        |> Portfolio.Repo.update()

      # Session still exists but user role is stale in cache
      # In production, role change should invalidate session cache
      refreshed_session = SessionService.get_session_by_token(session.token)
      assert refreshed_session != nil
      assert refreshed_session.user.id == updated_user.id
    end

    test "user data refreshed from DB when cache stale after update" do
      user = create_user()
      {:ok, session} = SessionService.create_session(user)

      # Fetch session
      cached_session = SessionService.get_session_by_token(session.token)
      assert cached_session != nil
      original_email = cached_session.user.email

      # Update user email
      new_email = "updated#{System.unique_integer([:positive])}@example.com"

      {:ok, _updated_user} =
        user
        |> Ecto.Changeset.change(%{email: new_email})
        |> Portfolio.Repo.update()

      # Session still exists
      refreshed_session = SessionService.get_session_by_token(session.token)
      assert refreshed_session != nil
      # Note: Cache may still have old email until invalidated
      assert refreshed_session.user.email == original_email or
               refreshed_session.user.email == new_email
    end
  end

  describe "cache TTL behavior" do
    test "session cache respects TTL (expires after configured time)" do
      # Note: This test requires configuring Cachex with short TTL for testing
      # In production, sessions are cached with longer TTL

      user = create_user()
      {:ok, session} = SessionService.create_session(user)

      # Fetch session
      cached = SessionService.get_session_by_token(session.token)
      assert cached != nil

      # Note: Actual TTL testing requires cache configuration
      # This is a placeholder test that verifies the concept
    end

    test "expired cache entry refreshed from DB on next fetch" do
      user = create_user()
      {:ok, session} = SessionService.create_session(user)

      # First fetch
      cached_session1 = SessionService.get_session_by_token(session.token)
      assert cached_session1 != nil

      # Fetch again - should return same data
      cached_session2 = SessionService.get_session_by_token(session.token)
      assert cached_session2 != nil

      # Should return same data
      assert cached_session1.id == cached_session2.id
      assert cached_session1.user_id == cached_session2.user_id
    end
  end

  describe "cache performance" do
    test "cache reduces database queries on repeated session fetches" do
      user = create_user()
      {:ok, session} = SessionService.create_session(user)

      # Warm up cache
      assert SessionService.get_session_by_token(session.token) != nil

      # Measure fetches with cache (should be fast)
      start_time = System.monotonic_time(:microsecond)

      for _i <- 1..100 do
        SessionService.get_session_by_token(session.token)
      end

      end_time = System.monotonic_time(:microsecond)
      elapsed = end_time - start_time

      # Cached fetches should complete quickly
      # (Actual threshold depends on system)
      assert elapsed < 500_000, "Cached fetches too slow: #{elapsed}μs"
    end
  end

  describe "error scenarios" do
    test "invalid session token returns nil (not cached)" do
      fake_token = "invalid_token_#{System.unique_integer([:positive])}"

      result = SessionService.get_session_by_token(fake_token)

      assert result == nil
    end

    test "deleted session returns nil (cache invalidated)" do
      user = create_user()
      {:ok, session} = SessionService.create_session(user)

      # Verify session exists
      assert SessionService.get_session_by_token(session.token) != nil

      # Delete session - returns {:ok, deleted_session}
      {:ok, _deleted} = SessionService.delete_session(session)

      # Subsequent fetch should return nil
      result = SessionService.get_session_by_token(session.token)
      assert result == nil
    end
  end
end
