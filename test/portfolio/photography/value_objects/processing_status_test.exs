defmodule Portfolio.Photography.ValueObjects.ProcessingStatusTest do
  use ExUnit.Case, async: true

  alias Portfolio.Photography.ValueObjects.ProcessingStatus

  describe "new/1 with atoms" do
    test "creates ProcessingStatus for :pending" do
      assert {:ok, status} = ProcessingStatus.new(:pending)
      assert status.value == :pending
    end

    test "creates ProcessingStatus for :processing" do
      assert {:ok, status} = ProcessingStatus.new(:processing)
      assert status.value == :processing
    end

    test "creates ProcessingStatus for :completed" do
      assert {:ok, status} = ProcessingStatus.new(:completed)
      assert status.value == :completed
    end

    test "creates ProcessingStatus for :failed" do
      assert {:ok, status} = ProcessingStatus.new(:failed)
      assert status.value == :failed
    end

    test "returns error for invalid atom" do
      assert {:error, :invalid_status} = ProcessingStatus.new(:invalid)
    end

    test "returns error for unknown atom" do
      assert {:error, :invalid_status} = ProcessingStatus.new(:cancelled)
    end
  end

  describe "new/1 with strings" do
    test "creates ProcessingStatus for 'pending'" do
      assert {:ok, status} = ProcessingStatus.new("pending")
      assert status.value == :pending
    end

    test "creates ProcessingStatus for 'processing'" do
      assert {:ok, status} = ProcessingStatus.new("processing")
      assert status.value == :processing
    end

    test "creates ProcessingStatus for 'completed'" do
      assert {:ok, status} = ProcessingStatus.new("completed")
      assert status.value == :completed
    end

    test "creates ProcessingStatus for 'failed'" do
      assert {:ok, status} = ProcessingStatus.new("failed")
      assert status.value == :failed
    end

    test "returns error for invalid string" do
      assert {:error, :invalid_status} = ProcessingStatus.new("invalid")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_status} = ProcessingStatus.new("")
    end
  end

  describe "new!/1" do
    test "returns ProcessingStatus for valid input" do
      status = ProcessingStatus.new!(:pending)
      assert status.value == :pending
    end

    test "raises ArgumentError for invalid input" do
      assert_raise ArgumentError, ~r/Invalid processing status/, fn ->
        ProcessingStatus.new!(:invalid)
      end
    end
  end

  describe "default/0" do
    test "returns pending status" do
      status = ProcessingStatus.default()
      assert status.value == :pending
    end
  end

  describe "transition/2 - valid transitions" do
    test "pending -> processing" do
      {:ok, pending} = ProcessingStatus.new(:pending)
      assert {:ok, processing} = ProcessingStatus.transition(pending, :processing)
      assert processing.value == :processing
    end

    test "processing -> completed" do
      {:ok, processing} = ProcessingStatus.new(:processing)
      assert {:ok, completed} = ProcessingStatus.transition(processing, :completed)
      assert completed.value == :completed
    end

    test "processing -> failed" do
      {:ok, processing} = ProcessingStatus.new(:processing)
      assert {:ok, failed} = ProcessingStatus.transition(processing, :failed)
      assert failed.value == :failed
    end

    test "failed -> pending (retry)" do
      {:ok, failed} = ProcessingStatus.new(:failed)
      assert {:ok, pending} = ProcessingStatus.transition(failed, :pending)
      assert pending.value == :pending
    end
  end

  describe "transition/2 - invalid transitions" do
    test "pending -> completed (must go through processing)" do
      {:ok, pending} = ProcessingStatus.new(:pending)
      assert {:error, :invalid_transition} = ProcessingStatus.transition(pending, :completed)
    end

    test "pending -> failed (must go through processing)" do
      {:ok, pending} = ProcessingStatus.new(:pending)
      assert {:error, :invalid_transition} = ProcessingStatus.transition(pending, :failed)
    end

    test "pending -> pending (no self-transition)" do
      {:ok, pending} = ProcessingStatus.new(:pending)
      assert {:error, :invalid_transition} = ProcessingStatus.transition(pending, :pending)
    end

    test "processing -> pending (no going back)" do
      {:ok, processing} = ProcessingStatus.new(:processing)
      assert {:error, :invalid_transition} = ProcessingStatus.transition(processing, :pending)
    end

    test "completed -> any (terminal state)" do
      {:ok, completed} = ProcessingStatus.new(:completed)
      assert {:error, :invalid_transition} = ProcessingStatus.transition(completed, :pending)
      assert {:error, :invalid_transition} = ProcessingStatus.transition(completed, :processing)
      assert {:error, :invalid_transition} = ProcessingStatus.transition(completed, :failed)
    end

    test "failed -> processing (must retry via pending)" do
      {:ok, failed} = ProcessingStatus.new(:failed)
      assert {:error, :invalid_transition} = ProcessingStatus.transition(failed, :processing)
    end

    test "failed -> completed (must retry via pending)" do
      {:ok, failed} = ProcessingStatus.new(:failed)
      assert {:error, :invalid_transition} = ProcessingStatus.transition(failed, :completed)
    end

    test "transition to invalid status" do
      {:ok, pending} = ProcessingStatus.new(:pending)
      assert {:error, :invalid_transition} = ProcessingStatus.transition(pending, :cancelled)
    end
  end

  describe "in_progress?/1" do
    test "returns true for pending" do
      {:ok, status} = ProcessingStatus.new(:pending)
      assert ProcessingStatus.in_progress?(status)
    end

    test "returns true for processing" do
      {:ok, status} = ProcessingStatus.new(:processing)
      assert ProcessingStatus.in_progress?(status)
    end

    test "returns false for completed" do
      {:ok, status} = ProcessingStatus.new(:completed)
      refute ProcessingStatus.in_progress?(status)
    end

    test "returns false for failed" do
      {:ok, status} = ProcessingStatus.new(:failed)
      refute ProcessingStatus.in_progress?(status)
    end
  end

  describe "terminal?/1" do
    test "returns false for pending" do
      {:ok, status} = ProcessingStatus.new(:pending)
      refute ProcessingStatus.terminal?(status)
    end

    test "returns false for processing" do
      {:ok, status} = ProcessingStatus.new(:processing)
      refute ProcessingStatus.terminal?(status)
    end

    test "returns true for completed" do
      {:ok, status} = ProcessingStatus.new(:completed)
      assert ProcessingStatus.terminal?(status)
    end

    test "returns true for failed" do
      {:ok, status} = ProcessingStatus.new(:failed)
      assert ProcessingStatus.terminal?(status)
    end
  end

  describe "succeeded?/1" do
    test "returns true only for completed" do
      {:ok, completed} = ProcessingStatus.new(:completed)
      assert ProcessingStatus.succeeded?(completed)

      {:ok, pending} = ProcessingStatus.new(:pending)
      refute ProcessingStatus.succeeded?(pending)

      {:ok, processing} = ProcessingStatus.new(:processing)
      refute ProcessingStatus.succeeded?(processing)

      {:ok, failed} = ProcessingStatus.new(:failed)
      refute ProcessingStatus.succeeded?(failed)
    end
  end

  describe "failed?/1" do
    test "returns true only for failed" do
      {:ok, failed} = ProcessingStatus.new(:failed)
      assert ProcessingStatus.failed?(failed)

      {:ok, pending} = ProcessingStatus.new(:pending)
      refute ProcessingStatus.failed?(pending)

      {:ok, processing} = ProcessingStatus.new(:processing)
      refute ProcessingStatus.failed?(processing)

      {:ok, completed} = ProcessingStatus.new(:completed)
      refute ProcessingStatus.failed?(completed)
    end
  end

  describe "can_retry?/1" do
    test "returns true only for failed" do
      {:ok, failed} = ProcessingStatus.new(:failed)
      assert ProcessingStatus.can_retry?(failed)

      {:ok, pending} = ProcessingStatus.new(:pending)
      refute ProcessingStatus.can_retry?(pending)

      {:ok, processing} = ProcessingStatus.new(:processing)
      refute ProcessingStatus.can_retry?(processing)

      {:ok, completed} = ProcessingStatus.new(:completed)
      refute ProcessingStatus.can_retry?(completed)
    end
  end

  describe "to_atom/1" do
    test "returns atom value" do
      {:ok, status} = ProcessingStatus.new(:pending)
      assert ProcessingStatus.to_atom(status) == :pending
    end
  end

  describe "to_string/1" do
    test "returns string value" do
      {:ok, status} = ProcessingStatus.new(:pending)
      assert ProcessingStatus.to_string(status) == "pending"
    end
  end

  describe "equal?/2" do
    test "returns true for same status" do
      {:ok, s1} = ProcessingStatus.new(:pending)
      {:ok, s2} = ProcessingStatus.new(:pending)
      assert ProcessingStatus.equal?(s1, s2)
    end

    test "returns false for different status" do
      {:ok, s1} = ProcessingStatus.new(:pending)
      {:ok, s2} = ProcessingStatus.new(:processing)
      refute ProcessingStatus.equal?(s1, s2)
    end
  end

  describe "valid_statuses/0" do
    test "returns all valid statuses" do
      statuses = ProcessingStatus.valid_statuses()
      assert :pending in statuses
      assert :processing in statuses
      assert :completed in statuses
      assert :failed in statuses
      assert length(statuses) == 4
    end
  end

  describe "valid_transitions/0" do
    test "returns all valid transitions" do
      transitions = ProcessingStatus.valid_transitions()
      assert {:pending, :processing} in transitions
      assert {:processing, :completed} in transitions
      assert {:processing, :failed} in transitions
      assert {:failed, :pending} in transitions
      assert length(transitions) == 4
    end
  end

  describe "String.Chars protocol" do
    test "converts to string via to_string/1" do
      {:ok, status} = ProcessingStatus.new(:processing)
      assert to_string(status) == "processing"
    end

    test "works in string interpolation" do
      {:ok, status} = ProcessingStatus.new(:completed)
      assert "Status: #{status}" == "Status: completed"
    end
  end

  describe "complete workflow" do
    test "simulates successful processing workflow" do
      # Start with default (pending)
      status = ProcessingStatus.default()
      assert status.value == :pending
      assert ProcessingStatus.in_progress?(status)

      # Transition to processing
      {:ok, status} = ProcessingStatus.transition(status, :processing)
      assert status.value == :processing
      assert ProcessingStatus.in_progress?(status)

      # Complete successfully
      {:ok, status} = ProcessingStatus.transition(status, :completed)
      assert status.value == :completed
      assert ProcessingStatus.terminal?(status)
      assert ProcessingStatus.succeeded?(status)
      refute ProcessingStatus.can_retry?(status)
    end

    test "simulates failed processing with retry" do
      # Start with pending
      {:ok, status} = ProcessingStatus.new(:pending)

      # Transition to processing
      {:ok, status} = ProcessingStatus.transition(status, :processing)

      # Fail
      {:ok, status} = ProcessingStatus.transition(status, :failed)
      assert ProcessingStatus.terminal?(status)
      assert ProcessingStatus.failed?(status)
      assert ProcessingStatus.can_retry?(status)

      # Retry (back to pending)
      {:ok, status} = ProcessingStatus.transition(status, :pending)
      assert status.value == :pending
      assert ProcessingStatus.in_progress?(status)

      # Process again and complete
      {:ok, status} = ProcessingStatus.transition(status, :processing)
      {:ok, status} = ProcessingStatus.transition(status, :completed)
      assert ProcessingStatus.succeeded?(status)
    end
  end
end
