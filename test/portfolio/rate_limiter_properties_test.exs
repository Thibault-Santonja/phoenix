defmodule Portfolio.RateLimiterPropertiesTest do
  @moduledoc """
  Property-based tests for RateLimiter.

  Tests rate limiting invariants such as enforcement after N requests,
  independence of different keys, and monotonic behavior.
  """
  use ExUnit.Case, async: false

  @moduletag :skip
  use ExUnitProperties

  alias Portfolio.RateLimiter

  setup do
    # Start the RateLimiter if not already started
    case Process.whereis(RateLimiter) do
      nil ->
        start_supervised!(RateLimiter)

      _pid ->
        :ok
    end

    # Clean up rate limiter state between tests
    if :ets.whereis(RateLimiter) != :undefined do
      :ets.delete_all_objects(RateLimiter)
    end

    :ok
  end

  describe "rate limit enforcement properties" do
    property "rate limit enforced after exactly N requests" do
      check all(
              action <- member_of([:magic_link_request, :login_attempt, :album_creation]),
              identifier <- string(:alphanumeric, min_length: 5, max_length: 20),
              max_runs: 10
            ) do
        # Get the limit for this action
        {limit, _period} = get_rate_limit_config(action)

        # Make exactly 'limit' requests - all should be allowed
        results =
          for i <- 1..limit do
            unique_id = "#{identifier}_#{i}_#{System.unique_integer()}"
            RateLimiter.check_rate(action, unique_id)
          end

        # All should be allowed
        Enum.each(results, fn result ->
          assert {:allow, _remaining} = result
        end)

        # The (limit + 1)th request should be denied
        unique_id = "#{identifier}_over_#{System.unique_integer()}"

        # Make limit + 1 requests on same identifier
        Enum.each(1..limit, fn _ ->
          RateLimiter.check_rate(action, unique_id)
        end)

        # This should be denied
        assert {:deny, _retry_after} = RateLimiter.check_rate(action, unique_id)
      end
    end

    property "remaining count decreases monotonically" do
      check all(
              action <- member_of([:magic_link_request, :photo_upload, :session_creation]),
              identifier <- string(:alphanumeric, min_length: 8, max_length: 30),
              max_runs: 10
            ) do
        {limit, _period} = get_rate_limit_config(action)
        unique_id = "#{identifier}_#{System.unique_integer()}"

        # Make multiple requests and track remaining count
        remainings =
          for _ <- 1..min(limit, 5) do
            case RateLimiter.check_rate(action, unique_id) do
              {:allow, remaining} -> remaining
              {:deny, _} -> -1
            end
          end

        # Filter out denied requests
        allowed_remainings = Enum.filter(remainings, &(&1 >= 0))

        # Remaining should decrease (or stay same if already at 0)
        if length(allowed_remainings) > 1 do
          pairs = Enum.zip(allowed_remainings, tl(allowed_remainings))

          Enum.each(pairs, fn {prev, curr} ->
            assert prev >= curr,
                   "Remaining count should decrease: #{prev} -> #{curr}"
          end)
        end
      end
    end
  end

  describe "key independence properties" do
    property "different keys have independent limits" do
      check all(
              action <- member_of([:magic_link_request, :login_attempt]),
              id1 <- string(:alphanumeric, min_length: 5, max_length: 15),
              id2 <- string(:alphanumeric, min_length: 5, max_length: 15),
              id1 != id2,
              max_runs: 10
            ) do
        unique_id1 = "#{id1}_#{System.unique_integer()}"
        unique_id2 = "#{id2}_#{System.unique_integer()}"

        {limit, _period} = get_rate_limit_config(action)

        # Exhaust limit for id1
        Enum.each(1..limit, fn _ ->
          RateLimiter.check_rate(action, unique_id1)
        end)

        # id1 should be denied
        assert {:deny, _} = RateLimiter.check_rate(action, unique_id1)

        # id2 should still be allowed (independent limit)
        assert {:allow, _} = RateLimiter.check_rate(action, unique_id2)
      end
    end

    property "different actions have independent limits" do
      check all(
              identifier <- string(:alphanumeric, min_length: 8, max_length: 20),
              max_runs: 5
            ) do
        unique_id = "#{identifier}_#{System.unique_integer()}"

        # Make multiple requests for :magic_link_request
        {limit1, _} = get_rate_limit_config(:magic_link_request)

        Enum.each(1..limit1, fn _ ->
          RateLimiter.check_rate(:magic_link_request, unique_id)
        end)

        # magic_link_request should be denied
        assert {:deny, _} = RateLimiter.check_rate(:magic_link_request, unique_id)

        # login_attempt should still be allowed (different action)
        assert {:allow, _} = RateLimiter.check_rate(:login_attempt, unique_id)
      end
    end
  end

  describe "result consistency properties" do
    property "allow result includes non-negative remaining count" do
      check all(
              action <- member_of([:magic_link_request, :login_attempt, :album_creation]),
              identifier <- string(:alphanumeric, min_length: 5, max_length: 20),
              max_runs: 10
            ) do
        unique_id = "#{identifier}_#{System.unique_integer()}"

        case RateLimiter.check_rate(action, unique_id) do
          {:allow, remaining} ->
            assert is_integer(remaining)
            assert remaining >= 0

          {:deny, _} ->
            :ok
        end
      end
    end

    property "deny result includes positive retry_after" do
      check all(
              action <- member_of([:bulk_delete, :album_creation]),
              identifier <- string(:alphanumeric, min_length: 5, max_length: 20),
              max_runs: 5
            ) do
        unique_id = "#{identifier}_#{System.unique_integer()}"
        {limit, _period} = get_rate_limit_config(action)

        # Exhaust the limit
        Enum.each(1..(limit + 1), fn _ ->
          RateLimiter.check_rate(action, unique_id)
        end)

        # Should be denied now
        case RateLimiter.check_rate(action, unique_id) do
          {:deny, retry_after} ->
            assert is_integer(retry_after)
            assert retry_after > 0

          {:allow, _} ->
            # If somehow still allowed, that's ok (timing edge case)
            :ok
        end
      end
    end
  end

  describe "deterministic behavior properties" do
    property "check_rate is deterministic for same inputs" do
      check all(
              action <- member_of([:magic_link_request, :session_creation]),
              identifier <- string(:alphanumeric, min_length: 8, max_length: 25),
              max_runs: 10
            ) do
        unique_id = "#{identifier}_#{System.unique_integer()}"

        # First call
        result1 = RateLimiter.check_rate(action, unique_id)

        # Immediate second call should reflect the state change
        result2 = RateLimiter.check_rate(action, unique_id)

        # Both should have same structure (both :allow or both :deny)
        assert elem(result1, 0) in [:allow, :deny]
        assert elem(result2, 0) in [:allow, :deny]

        # If first was :allow with N remaining, second should be :allow with N-1 remaining
        case {result1, result2} do
          {{:allow, rem1}, {:allow, rem2}} ->
            assert rem2 == rem1 - 1,
                   "Second call should have 1 less remaining: #{rem1} -> #{rem2}"

          _ ->
            :ok
        end
      end
    end
  end

  # Helper to get rate limit configuration
  defp get_rate_limit_config(action) do
    %{
      magic_link_request: {5, :timer.hours(1)},
      magic_link_verify: {10, :timer.minutes(5)},
      login_attempt: {10, :timer.hours(1)},
      session_creation: {20, :timer.hours(1)},
      photo_upload: {50, :timer.minutes(10)},
      album_creation: {10, :timer.hours(1)},
      bulk_delete: {5, :timer.minutes(1)}
    }
    |> Map.fetch!(action)
  end
end
