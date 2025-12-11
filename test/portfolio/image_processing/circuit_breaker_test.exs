defmodule Portfolio.ImageProcessing.CircuitBreakerTest do
  use ExUnit.Case, async: false

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
end
