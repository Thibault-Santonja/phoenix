defmodule Portfolio.ImageProcessing.CircuitBreakerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Portfolio.ImageProcessing.CircuitBreaker

  @fuse_name :test_circuit_breaker
  @fuse_options {{:standard, 5, 60_000}, {:reset, 30_000}}

  setup do
    # Install and reset fuse before each test
    :fuse.install(@fuse_name, @fuse_options)
    _ = :fuse.reset(@fuse_name)
    :ok
  end

  describe "install/0" do
    test "installs the circuit breaker fuse" do
      assert CircuitBreaker.install() == :ok
    end

    test "returns ok if already installed" do
      CircuitBreaker.install()
      assert CircuitBreaker.install() == :ok
    end
  end

  describe "call/2" do
    test "returns ok tuple when function succeeds" do
      result = CircuitBreaker.call(@fuse_name, fn -> {:ok, :success} end)
      assert result == {:ok, :success}
    end

    test "handles 3-element ok tuple from image operations" do
      # VipsAdapter.load_image returns {:ok, image, dimensions}
      result =
        CircuitBreaker.call(@fuse_name, fn ->
          {:ok, :mock_image, %{width: 1920, height: 1080}}
        end)

      assert result == {:ok, {:ok, :mock_image, %{width: 1920, height: 1080}}}
    end

    test "returns error tuple when function fails" do
      result = CircuitBreaker.call(@fuse_name, fn -> {:error, :some_error} end)
      assert result == {:error, :some_error}
    end

    test "handles exceptions and records failure" do
      result =
        CircuitBreaker.call(@fuse_name, fn ->
          raise "test error"
        end)

      assert {:error, {:exception, %RuntimeError{message: "test error"}}} = result
    end

    test "handles exits and records failure" do
      result =
        CircuitBreaker.call(@fuse_name, fn ->
          exit(:test_exit)
        end)

      assert result == {:error, {:exit, :test_exit}}
    end

    test "returns circuit_blown when circuit is open" do
      # Trip the circuit by causing failures
      :fuse.install(@fuse_name, {{:standard, 2, 60_000}, {:reset, 30_000}})

      CircuitBreaker.call(@fuse_name, fn -> {:error, :fail1} end)
      CircuitBreaker.call(@fuse_name, fn -> {:error, :fail2} end)
      CircuitBreaker.call(@fuse_name, fn -> {:error, :fail3} end)

      # Circuit should be blown now
      result = CircuitBreaker.call(@fuse_name, fn -> {:ok, :should_not_run} end)
      assert result == {:error, :circuit_blown}
    end

    test "installs default fuse if not found and retries" do
      # The CircuitBreaker.call/2 with a custom fuse name will call install()
      # which installs the default :image_processing fuse
      # Test using the default fuse name to verify this behavior
      :fuse.remove(:image_processing)

      result = CircuitBreaker.call(fn -> {:ok, :auto_installed} end)
      assert result == {:ok, :auto_installed}
    end
  end

  describe "blown?/1" do
    test "returns false when circuit is closed" do
      :fuse.install(@fuse_name, {{:standard, 5, 60_000}, {:reset, 30_000}})
      refute CircuitBreaker.blown?(@fuse_name)
    end

    test "returns true when circuit is open" do
      :fuse.install(@fuse_name, {{:standard, 1, 60_000}, {:reset, 30_000}})

      # Trip the circuit
      CircuitBreaker.call(@fuse_name, fn -> {:error, :trip} end)
      CircuitBreaker.call(@fuse_name, fn -> {:error, :trip} end)

      assert CircuitBreaker.blown?(@fuse_name)
    end
  end

  describe "reset/1" do
    test "resets a blown circuit" do
      :fuse.install(@fuse_name, {{:standard, 1, 60_000}, {:reset, 30_000}})

      # Trip the circuit
      CircuitBreaker.call(@fuse_name, fn -> {:error, :trip} end)
      CircuitBreaker.call(@fuse_name, fn -> {:error, :trip} end)

      assert CircuitBreaker.blown?(@fuse_name)

      # Reset
      assert CircuitBreaker.reset(@fuse_name) == :ok
      refute CircuitBreaker.blown?(@fuse_name)
    end
  end

  describe "status/1" do
    test "returns :ok when circuit is closed" do
      :fuse.install(@fuse_name, {{:standard, 5, 60_000}, {:reset, 30_000}})
      assert CircuitBreaker.status(@fuse_name) == :ok
    end

    test "returns :blown when circuit is open" do
      :fuse.install(@fuse_name, {{:standard, 1, 60_000}, {:reset, 30_000}})

      # Trip the circuit
      CircuitBreaker.call(@fuse_name, fn -> {:error, :trip} end)
      CircuitBreaker.call(@fuse_name, fn -> {:error, :trip} end)

      assert CircuitBreaker.status(@fuse_name) == :blown
    end

    test "returns error when fuse not found" do
      assert CircuitBreaker.status(:nonexistent_fuse) == {:error, :not_found}
    end
  end

  describe "logging behavior" do
    test "logs warning when operation fails" do
      log =
        capture_log(fn ->
          CircuitBreaker.call(@fuse_name, fn -> {:error, :processing_failed} end)
        end)

      assert log =~ "Image processing operation failed"
      assert log =~ "processing_failed"
    end

    test "logs error when exception occurs" do
      log =
        capture_log(fn ->
          CircuitBreaker.call(@fuse_name, fn -> raise "kaboom" end)
        end)

      assert log =~ "Image processing exception"
      assert log =~ "kaboom"
    end

    test "logs error when process exits" do
      log =
        capture_log(fn ->
          CircuitBreaker.call(@fuse_name, fn -> exit(:process_died) end)
        end)

      assert log =~ "Image processing exit"
      assert log =~ "process_died"
    end

    test "logs warning when circuit is blown" do
      :fuse.install(@fuse_name, {{:standard, 1, 60_000}, {:reset, 30_000}})

      # Trip the circuit first
      CircuitBreaker.call(@fuse_name, fn -> {:error, :trip} end)
      CircuitBreaker.call(@fuse_name, fn -> {:error, :trip} end)

      # Now capture log for the blown circuit call
      log =
        capture_log(fn ->
          CircuitBreaker.call(@fuse_name, fn -> {:ok, :wont_run} end)
        end)

      assert log =~ "Circuit breaker open"
    end

    test "reset returns :ok" do
      # Note: The info-level log message is not captured in test config (level: :warning)
      # We test the behavior instead of the log output
      assert CircuitBreaker.reset(@fuse_name) == :ok
    end
  end

  describe "circuit recovery" do
    test "allows calls after reset from blown state" do
      :fuse.install(@fuse_name, {{:standard, 1, 60_000}, {:reset, 30_000}})

      # Trip the circuit
      CircuitBreaker.call(@fuse_name, fn -> {:error, :trip} end)
      CircuitBreaker.call(@fuse_name, fn -> {:error, :trip} end)

      assert CircuitBreaker.blown?(@fuse_name)
      assert CircuitBreaker.call(@fuse_name, fn -> {:ok, :test} end) == {:error, :circuit_blown}

      # Reset and verify recovery
      CircuitBreaker.reset(@fuse_name)
      refute CircuitBreaker.blown?(@fuse_name)
      assert CircuitBreaker.call(@fuse_name, fn -> {:ok, :recovered} end) == {:ok, :recovered}
    end

    test "successful call after reset does not trip circuit" do
      :fuse.install(@fuse_name, {{:standard, 2, 60_000}, {:reset, 30_000}})

      # Cause one failure (not enough to trip)
      CircuitBreaker.call(@fuse_name, fn -> {:error, :fail1} end)
      refute CircuitBreaker.blown?(@fuse_name)

      # Successful call - circuit should remain closed
      assert CircuitBreaker.call(@fuse_name, fn -> {:ok, :success} end) == {:ok, :success}
      refute CircuitBreaker.blown?(@fuse_name)
    end
  end

  describe "edge cases" do
    test "handles throw values" do
      # throw is not caught by rescue/catch :exit in the current implementation
      # so it propagates up - we need to catch it here
      assert catch_throw(
               CircuitBreaker.call(@fuse_name, fn ->
                 throw(:unexpected_throw)
               end)
             ) == :unexpected_throw
    end

    test "handles function returning bare value (not tuple)" do
      # The function returns a bare value - this doesn't match {:ok, _} or {:error, _}
      # causing a CaseClauseError which is caught as an exception
      result =
        CircuitBreaker.call(@fuse_name, fn ->
          :bare_atom_return
        end)

      assert {:error, {:exception, %CaseClauseError{term: :bare_atom_return}}} = result
    end

    test "handles nil return value" do
      result =
        CircuitBreaker.call(@fuse_name, fn ->
          nil
        end)

      # nil doesn't match {:ok, _} or {:error, _}, causing CaseClauseError
      assert {:error, {:exception, %CaseClauseError{term: nil}}} = result
    end

    test "concurrent calls respect circuit state" do
      :fuse.install(@fuse_name, {{:standard, 2, 60_000}, {:reset, 30_000}})

      # Trip the circuit
      CircuitBreaker.call(@fuse_name, fn -> {:error, :fail1} end)
      CircuitBreaker.call(@fuse_name, fn -> {:error, :fail2} end)
      CircuitBreaker.call(@fuse_name, fn -> {:error, :fail3} end)

      # Concurrent calls should all see blown circuit
      tasks =
        for _i <- 1..5 do
          Task.async(fn ->
            CircuitBreaker.call(@fuse_name, fn -> {:ok, :should_not_run} end)
          end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == {:error, :circuit_blown}))
    end
  end
end
