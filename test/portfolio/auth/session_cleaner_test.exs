defmodule Portfolio.Auth.SessionCleanerTest do
  use Portfolio.DataCase, async: false

  alias Portfolio.Auth
  alias Portfolio.Auth.{SessionCleaner, UserSession}
  alias Portfolio.Repo

  import PortfolioTest.Fixtures.AuthFixtures

  describe "cleanup_now/0" do
    test "deletes expired sessions" do
      user = create_user()

      # Create an expired session by setting last_activity_at to 2 hours ago (default expiry is 1 hour)
      expired_session = %UserSession{
        user_id: user.id,
        token: "test-token-expired-#{System.unique_integer([:positive])}",
        last_activity_at:
          DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.truncate(:second)
      }

      {:ok, expired_session} = Repo.insert(expired_session)

      # Create a valid session
      {:ok, valid_session} = Auth.create_session(user)

      # Cleanup expired sessions
      assert {:ok, count} = SessionCleaner.cleanup_now()
      assert count >= 1

      # Valid session should still exist
      assert %UserSession{} = Auth.get_session!(valid_session.id)

      # Expired session should be gone
      assert_raise Ecto.NoResultsError, fn ->
        Auth.get_session!(expired_session.id)
      end
    end

    test "returns 0 when no expired sessions exist" do
      # Clean up any existing expired sessions first
      SessionCleaner.cleanup_now()

      # Now should return 0
      assert {:ok, 0} = SessionCleaner.cleanup_now()
    end

    test "handles cleanup with multiple expired sessions" do
      user = create_user()

      # Create multiple expired sessions
      for i <- 1..3 do
        expired_session = %UserSession{
          user_id: user.id,
          token: "token-expired-#{i}-#{System.unique_integer([:positive])}",
          last_activity_at:
            DateTime.add(DateTime.utc_now(), -7200 - i * 1000, :second)
            |> DateTime.truncate(:second)
        }

        Repo.insert!(expired_session)
      end

      assert {:ok, count} = SessionCleaner.cleanup_now()
      assert count >= 3
    end
  end

  describe "handle_info/2 :cleanup" do
    test "performs cleanup and reschedules" do
      user = create_user()

      # Create an expired session
      expired_session = %UserSession{
        user_id: user.id,
        token: "expired-#{System.unique_integer([:positive])}",
        last_activity_at:
          DateTime.add(DateTime.utc_now(), -7200, :second) |> DateTime.truncate(:second)
      }

      {:ok, expired_session} = Repo.insert(expired_session)

      # Send cleanup message directly to the running cleaner
      send(SessionCleaner, :cleanup)

      # Give it time to process
      Process.sleep(100)

      # Session should be deleted
      assert_raise Ecto.NoResultsError, fn ->
        Auth.get_session!(expired_session.id)
      end
    end
  end
end
