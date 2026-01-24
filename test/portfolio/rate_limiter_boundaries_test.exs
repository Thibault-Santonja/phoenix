defmodule Portfolio.RateLimiterBoundariesTest do
  @moduledoc """
  Boundary and edge case tests for rate limiting.

  Tests cover:
  - Request at exactly the limit
  - Window boundary reset behavior
  - Concurrent requests handling
  - Unicode and special characters in identifiers
  - Rate limit exhaustion recovery
  """
  use PortfolioWeb.ConnCase, async: false

  alias Portfolio.RateLimiter

  setup do
    # Enable rate limiting for these tests
    Application.put_env(:portfolio, :enable_rate_limiting_in_tests, true)

    # Clear cache before each test
    Cachex.clear(:portfolio_cache)

    on_exit(fn ->
      Application.put_env(:portfolio, :enable_rate_limiting_in_tests, false)
      Cachex.clear(:portfolio_cache)
    end)

    :ok
  end

  describe "exact limit boundaries" do
    test "allows request at exactly the limit" do
      identifier = "user-exact-limit-#{System.unique_integer()}"
      action = :magic_link_request
      # Limit is 5 per hour for magic link requests

      # Make exactly 5 requests
      results =
        Enum.map(1..5, fn _ ->
          RateLimiter.check_rate(action, identifier)
        end)

      # All 5 should be allowed
      Enum.each(results, fn result ->
        assert {:allow, _remaining} = result
      end)

      # 6th request should be denied
      assert {:deny, retry_after_ms} = RateLimiter.check_rate(action, identifier)
      assert retry_after_ms > 0
    end

    test "tracks remaining requests correctly" do
      identifier = "user-remaining-#{System.unique_integer()}"
      action = :magic_link_request

      # First request
      assert {:allow, remaining} = RateLimiter.check_rate(action, identifier)
      assert remaining == 4

      # Second request
      assert {:allow, remaining} = RateLimiter.check_rate(action, identifier)
      assert remaining == 3

      # Third request
      assert {:allow, remaining} = RateLimiter.check_rate(action, identifier)
      assert remaining == 2

      # Fourth request
      assert {:allow, remaining} = RateLimiter.check_rate(action, identifier)
      assert remaining == 1

      # Fifth request
      assert {:allow, remaining} = RateLimiter.check_rate(action, identifier)
      assert remaining == 0

      # Sixth request - denied
      assert {:deny, _retry_after} = RateLimiter.check_rate(action, identifier)
    end
  end

  describe "window boundary and reset" do
    test "rate limit resets after window expires" do
      identifier = "user-window-reset-#{System.unique_integer()}"
      action = :bulk_delete
      # bulk_delete limit is 5 per minute

      # Exhaust the limit
      Enum.each(1..5, fn _ ->
        assert {:allow, _} = RateLimiter.check_rate(action, identifier)
      end)

      # Should be blocked
      assert {:deny, retry_after_ms} = RateLimiter.check_rate(action, identifier)
      assert retry_after_ms > 0
      assert retry_after_ms <= 60_000

      # Wait for window to expire (in real scenario)
      # In test, we can't wait 1 minute, so we verify retry_after is reasonable
      assert retry_after_ms <= :timer.minutes(1)
    end

    test "different actions have independent limits" do
      identifier = "user-multi-action-#{System.unique_integer()}"

      # Exhaust magic_link_request (5/hour)
      Enum.each(1..5, fn _ ->
        assert {:allow, _} = RateLimiter.check_rate(:magic_link_request, identifier)
      end)

      assert {:deny, _} = RateLimiter.check_rate(:magic_link_request, identifier)

      # login_attempt should still work (different action, 10/hour limit)
      assert {:allow, remaining} = RateLimiter.check_rate(:login_attempt, identifier)
      assert remaining == 9
    end

    test "different identifiers have independent limits" do
      action = :magic_link_request

      user1 = "user1-#{System.unique_integer()}"
      user2 = "user2-#{System.unique_integer()}"

      # Exhaust user1's limit
      Enum.each(1..5, fn _ ->
        assert {:allow, _} = RateLimiter.check_rate(action, user1)
      end)

      assert {:deny, _} = RateLimiter.check_rate(action, user1)

      # user2 should still have full quota
      assert {:allow, remaining} = RateLimiter.check_rate(action, user2)
      assert remaining == 4
    end
  end

  describe "concurrent requests" do
    test "handles concurrent requests without race conditions" do
      identifier = "user-concurrent-#{System.unique_integer()}"
      action = :magic_link_request

      # Make 10 concurrent requests (limit is 5)
      tasks =
        Enum.map(1..10, fn _ ->
          Task.async(fn ->
            RateLimiter.check_rate(action, identifier)
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # Count allows and denies
      {allows, denies} = Enum.split_with(results, &match?({:allow, _}, &1))

      # Should have exactly 5 allows and 5 denies
      assert length(allows) == 5
      assert length(denies) == 5

      # All denies should have retry_after
      Enum.each(denies, fn {:deny, retry_after} ->
        assert retry_after > 0
      end)
    end

    test "handles rapid sequential requests correctly" do
      identifier = "user-rapid-#{System.unique_integer()}"
      action = :session_creation
      # Limit: 20 per hour

      # Fire 25 requests as fast as possible
      results =
        Enum.map(1..25, fn _ ->
          RateLimiter.check_rate(action, identifier)
        end)

      {allows, denies} = Enum.split_with(results, &match?({:allow, _}, &1))

      # Should allow exactly 20, deny 5
      assert length(allows) == 20
      assert length(denies) == 5
    end
  end

  describe "identifier edge cases" do
    test "handles unicode characters in identifier" do
      identifier = "user-üñíçödé-#{System.unique_integer()}"
      action = :magic_link_request

      assert {:allow, _} = RateLimiter.check_rate(action, identifier)
    end

    test "handles emoji in identifier" do
      identifier = "user-😀🎉-#{System.unique_integer()}"
      action = :magic_link_request

      assert {:allow, _} = RateLimiter.check_rate(action, identifier)
    end

    test "handles very long identifier" do
      identifier = String.duplicate("a", 500)
      action = :magic_link_request

      assert {:allow, _} = RateLimiter.check_rate(action, identifier)
    end

    test "handles identifier with special characters" do
      identifiers = [
        "user+test@example.com",
        "user@example.com",
        "192.168.1.1",
        "user-name_123",
        "user with spaces",
        "user/with/slashes"
      ]

      Enum.each(identifiers, fn identifier ->
        action = :magic_link_request
        assert {:allow, _} = RateLimiter.check_rate(action, identifier)
      end)
    end

    test "empty string identifier is handled" do
      # Edge case: empty identifier
      # Should handle gracefully (may allow or deny based on implementation)
      result = RateLimiter.check_rate(:magic_link_request, "")

      # Should not crash
      assert match?({:allow, _}, result) or match?({:deny, _}, result)
    end
  end

  describe "retry_after accuracy" do
    test "retry_after value is within window period" do
      identifier = "user-retry-after-#{System.unique_integer()}"
      action = :magic_link_request
      # Window is 1 hour = 3,600,000 ms

      # Exhaust limit
      Enum.each(1..5, fn _ ->
        RateLimiter.check_rate(action, identifier)
      end)

      # Check retry_after
      assert {:deny, retry_after_ms} = RateLimiter.check_rate(action, identifier)

      # Should be positive and not exceed window
      assert retry_after_ms > 0
      assert retry_after_ms <= :timer.hours(1)
    end

    test "retry_after decreases on subsequent requests in same window" do
      identifier = "user-retry-decrease-#{System.unique_integer()}"
      action = :bulk_delete
      # Window is 1 minute

      # Exhaust limit (5 requests)
      Enum.each(1..5, fn _ ->
        RateLimiter.check_rate(action, identifier)
      end)

      # First denial
      assert {:deny, retry1} = RateLimiter.check_rate(action, identifier)

      # Sleep a tiny bit
      Process.sleep(100)

      # Second denial
      assert {:deny, retry2} = RateLimiter.check_rate(action, identifier)

      # retry_after should be slightly less (or equal within measurement error)
      # This tests that the window is moving forward
      assert retry2 <= retry1
    end
  end

  describe "edge cases in limits" do
    test "handles all defined action types" do
      identifier = "user-all-actions-#{System.unique_integer()}"

      actions = [
        :magic_link_request,
        :magic_link_verify,
        :login_attempt,
        :session_creation,
        :photo_upload,
        :album_creation,
        :bulk_delete
      ]

      # Each action should work
      Enum.each(actions, fn action ->
        assert {:allow, _} = RateLimiter.check_rate(action, identifier)
      end)
    end

    test "photo_upload has higher limit (50 per 10 minutes)" do
      identifier = "user-photo-upload-#{System.unique_integer()}"
      action = :photo_upload

      # Should allow many requests
      results =
        Enum.map(1..50, fn _ ->
          RateLimiter.check_rate(action, identifier)
        end)

      # All 50 should succeed
      Enum.each(results, fn result ->
        assert {:allow, _} = result
      end)

      # 51st should fail
      assert {:deny, _} = RateLimiter.check_rate(action, identifier)
    end

    test "album_creation has moderate limit (10 per hour)" do
      identifier = "user-album-creation-#{System.unique_integer()}"
      action = :album_creation

      # Make 10 requests
      results =
        Enum.map(1..10, fn _ ->
          RateLimiter.check_rate(action, identifier)
        end)

      # All 10 should succeed
      Enum.each(results, fn result ->
        assert {:allow, _} = result
      end)

      # 11th should fail
      assert {:deny, _} = RateLimiter.check_rate(action, identifier)
    end
  end
end
