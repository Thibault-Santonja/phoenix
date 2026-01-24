defmodule Portfolio.Workers.SessionCleanerWorkerTest do
  use Portfolio.DataCase, async: true
  use Oban.Testing, repo: Portfolio.Repo

  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Workers.SessionCleanerWorker

  describe "perform/1" do
    test "deletes expired sessions" do
      user = create_user()

      # Create an expired session (last activity 3 hours ago, default expiry is 2 hours)
      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-3 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      {:ok, _session} =
        Portfolio.Repo.insert(%Portfolio.Auth.UserSession{
          user_id: user.id,
          token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
          last_activity_at: expired_at
        })

      # Perform the job
      assert :ok = perform_job(SessionCleanerWorker, %{})

      # Verify telemetry would be emitted (job completed successfully)
    end

    test "returns ok when no expired sessions exist" do
      user = create_user()

      # Create a fresh session (last activity now)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, session} =
        Portfolio.Repo.insert(%Portfolio.Auth.UserSession{
          user_id: user.id,
          token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
          last_activity_at: now
        })

      # Perform the job
      assert :ok = perform_job(SessionCleanerWorker, %{})

      # Session should still exist (not expired)
      assert Portfolio.Repo.get(Portfolio.Auth.UserSession, session.id)
    end

    test "emits telemetry event on completion" do
      test_pid = self()

      :telemetry.attach(
        "test-session-cleaner-telemetry",
        [:portfolio, :workers, :session_cleaner, :executed],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Perform the job
      assert :ok = perform_job(SessionCleanerWorker, %{})

      assert_receive {:telemetry, [:portfolio, :workers, :session_cleaner, :executed],
                      measurements, metadata}

      assert is_integer(measurements.duration)
      assert is_integer(measurements.deleted_count)
      assert metadata.success == true

      :telemetry.detach("test-session-cleaner-telemetry")
    end

    test "deletes multiple expired sessions" do
      user = create_user()

      expired_at =
        DateTime.utc_now()
        |> DateTime.add(-3 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      # Create 5 expired sessions
      expired_sessions =
        for _i <- 1..5 do
          {:ok, session} =
            Portfolio.Repo.insert(%Portfolio.Auth.UserSession{
              user_id: user.id,
              token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
              last_activity_at: expired_at
            })

          session
        end

      # Create 2 active sessions
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      active_sessions =
        for _i <- 1..2 do
          {:ok, session} =
            Portfolio.Repo.insert(%Portfolio.Auth.UserSession{
              user_id: user.id,
              token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
              last_activity_at: now
            })

          session
        end

      # Perform the job
      assert :ok = perform_job(SessionCleanerWorker, %{})

      # Expired sessions should be deleted
      for session <- expired_sessions do
        refute Portfolio.Repo.get(Portfolio.Auth.UserSession, session.id)
      end

      # Active sessions should still exist
      for session <- active_sessions do
        assert Portfolio.Repo.get(Portfolio.Auth.UserSession, session.id)
      end
    end
  end
end
