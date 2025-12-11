defmodule Portfolio.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Portfolio.RateLimiter

  setup do
    # Reset all rate limits before each test
    RateLimiter.reset_all()
    :ok
  end

  describe "check_rate/2" do
    test "allows requests under the limit" do
      # magic_link_request has limit of 5 per hour
      assert {:allow, 4} = RateLimiter.check_rate(:magic_link_request, "test@example.com")
      assert {:allow, 3} = RateLimiter.check_rate(:magic_link_request, "test@example.com")
      assert {:allow, 2} = RateLimiter.check_rate(:magic_link_request, "test@example.com")
    end

    test "denies requests over the limit" do
      # Exhaust the limit (5 requests)
      for _ <- 1..5 do
        RateLimiter.check_rate(:magic_link_request, "spammer@example.com")
      end

      # 6th request should be denied
      assert {:deny, retry_after} =
               RateLimiter.check_rate(:magic_link_request, "spammer@example.com")

      assert is_integer(retry_after)
      assert retry_after > 0
    end

    test "rate limits are per identifier" do
      # Use up limit for user1
      for _ <- 1..5 do
        RateLimiter.check_rate(:magic_link_request, "user1@example.com")
      end

      # user1 is blocked
      assert {:deny, _} = RateLimiter.check_rate(:magic_link_request, "user1@example.com")

      # user2 still has full quota
      assert {:allow, 4} = RateLimiter.check_rate(:magic_link_request, "user2@example.com")
    end

    test "different actions have independent limits" do
      # Use up magic_link_request limit
      for _ <- 1..5 do
        RateLimiter.check_rate(:magic_link_request, "user@example.com")
      end

      # magic_link_request is blocked
      assert {:deny, _} = RateLimiter.check_rate(:magic_link_request, "user@example.com")

      # login_attempt still works (different action)
      assert {:allow, _} = RateLimiter.check_rate(:login_attempt, "user@example.com")
    end

    test "supports all defined actions" do
      actions = [
        :magic_link_request,
        :magic_link_verify,
        :login_attempt,
        :session_creation,
        :photo_upload,
        :album_creation,
        :bulk_delete
      ]

      for action <- actions do
        assert {:allow, _} = RateLimiter.check_rate(action, "test-identifier")
      end
    end
  end

  describe "reset/2" do
    test "resets rate limit for specific action and identifier" do
      # Use up the limit
      for _ <- 1..5 do
        RateLimiter.check_rate(:magic_link_request, "reset-test@example.com")
      end

      assert {:deny, _} = RateLimiter.check_rate(:magic_link_request, "reset-test@example.com")

      # Reset
      assert :ok = RateLimiter.reset(:magic_link_request, "reset-test@example.com")

      # Should be allowed again
      assert {:allow, _} = RateLimiter.check_rate(:magic_link_request, "reset-test@example.com")
    end

    test "reset only affects specified identifier" do
      # Use up limits for both users
      for _ <- 1..5 do
        RateLimiter.check_rate(:magic_link_request, "user-a@example.com")
        RateLimiter.check_rate(:magic_link_request, "user-b@example.com")
      end

      # Reset only user-a
      RateLimiter.reset(:magic_link_request, "user-a@example.com")

      # user-a is reset, user-b is still blocked
      assert {:allow, _} = RateLimiter.check_rate(:magic_link_request, "user-a@example.com")
      assert {:deny, _} = RateLimiter.check_rate(:magic_link_request, "user-b@example.com")
    end
  end

  describe "reset_all/0" do
    test "resets all rate limits" do
      # Use up limits for multiple actions and identifiers
      for _ <- 1..5 do
        RateLimiter.check_rate(:magic_link_request, "all-reset-1@example.com")
      end

      for _ <- 1..10 do
        RateLimiter.check_rate(:login_attempt, "192.168.1.1")
      end

      # Both are blocked
      assert {:deny, _} = RateLimiter.check_rate(:magic_link_request, "all-reset-1@example.com")
      assert {:deny, _} = RateLimiter.check_rate(:login_attempt, "192.168.1.1")

      # Reset all
      assert :ok = RateLimiter.reset_all()

      # Both are allowed again
      assert {:allow, _} = RateLimiter.check_rate(:magic_link_request, "all-reset-1@example.com")
      assert {:allow, _} = RateLimiter.check_rate(:login_attempt, "192.168.1.1")
    end
  end

  describe "reset_actions/1" do
    test "resets only specified actions" do
      # Use up limits
      for _ <- 1..5 do
        RateLimiter.check_rate(:magic_link_request, "actions-test@example.com")
      end

      for _ <- 1..10 do
        RateLimiter.check_rate(:login_attempt, "actions-test@example.com")
      end

      # Reset only magic_link_request
      assert :ok = RateLimiter.reset_actions([:magic_link_request])

      # magic_link_request is reset, login_attempt is still blocked
      assert {:allow, _} = RateLimiter.check_rate(:magic_link_request, "actions-test@example.com")
      assert {:deny, _} = RateLimiter.check_rate(:login_attempt, "actions-test@example.com")
    end
  end

  describe "reset_all_except/1" do
    test "resets all except specified actions" do
      # Use up limits
      for _ <- 1..5 do
        RateLimiter.check_rate(:magic_link_request, "except-test@example.com")
      end

      for _ <- 1..10 do
        RateLimiter.check_rate(:login_attempt, "except-test@example.com")
      end

      # Reset all except magic_link_request
      assert :ok = RateLimiter.reset_all_except([:magic_link_request])

      # magic_link_request is still blocked, login_attempt is reset
      assert {:deny, _} = RateLimiter.check_rate(:magic_link_request, "except-test@example.com")
      assert {:allow, _} = RateLimiter.check_rate(:login_attempt, "except-test@example.com")
    end
  end

  describe "limit/1" do
    test "returns configured limits for each action" do
      assert {5, period} = RateLimiter.limit(:magic_link_request)
      assert period == :timer.hours(1)

      assert {10, period} = RateLimiter.limit(:magic_link_verify)
      assert period == :timer.minutes(5)

      assert {10, period} = RateLimiter.limit(:login_attempt)
      assert period == :timer.hours(1)

      assert {20, period} = RateLimiter.limit(:session_creation)
      assert period == :timer.hours(1)

      assert {50, period} = RateLimiter.limit(:photo_upload)
      assert period == :timer.minutes(10)

      assert {10, period} = RateLimiter.limit(:album_creation)
      assert period == :timer.hours(1)

      assert {5, period} = RateLimiter.limit(:bulk_delete)
      assert period == :timer.minutes(1)
    end

    test "raises for unknown action" do
      assert_raise KeyError, fn ->
        RateLimiter.limit(:unknown_action)
      end
    end
  end
end
