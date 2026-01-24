defmodule Portfolio.DomainEventsTest do
  use ExUnit.Case, async: true

  alias Portfolio.DomainEvents

  # Short timeout for synchronous pub/sub (events are delivered immediately)
  @receive_timeout 50

  describe "publish/2 and subscribe/1" do
    test "publishes events to subscribed processes" do
      # Subscribe to a test event
      :ok = DomainEvents.subscribe(:test_event)

      # Publish an event
      payload = %{id: "123", message: "test"}
      :ok = DomainEvents.publish(:test_event, payload)

      # Assert the process receives the event
      assert_receive {:test_event, ^payload}, @receive_timeout
    end

    test "does not receive events without subscription" do
      # Don't subscribe, just publish
      payload = %{id: "456", message: "test2"}
      :ok = DomainEvents.publish(:unsubscribed_event, payload)

      # Should not receive any message (use 0 timeout - mailbox check only)
      refute_receive {:unsubscribed_event, _}, 0
    end

    test "multiple subscribers receive the same event" do
      # Create a test process that subscribes
      parent = self()
      ref1 = make_ref()
      ref2 = make_ref()

      subscriber1 =
        spawn_link(fn ->
          DomainEvents.subscribe(:multi_event)
          send(parent, {:ready, ref1})

          receive do
            {:multi_event, payload} ->
              send(parent, {:subscriber1, payload})
          end
        end)

      subscriber2 =
        spawn_link(fn ->
          DomainEvents.subscribe(:multi_event)
          send(parent, {:ready, ref2})

          receive do
            {:multi_event, payload} ->
              send(parent, {:subscriber2, payload})
          end
        end)

      # Wait for subscribers to be ready (deterministic)
      assert_receive {:ready, ^ref1}, @receive_timeout
      assert_receive {:ready, ^ref2}, @receive_timeout

      # Publish event
      payload = %{test: "data"}
      DomainEvents.publish(:multi_event, payload)

      # Both subscribers should receive
      assert_receive {:subscriber1, ^payload}, @receive_timeout
      assert_receive {:subscriber2, ^payload}, @receive_timeout

      # Cleanup
      Process.exit(subscriber1, :kill)
      Process.exit(subscriber2, :kill)
    end

    test "can subscribe to multiple event types" do
      DomainEvents.subscribe(:event_a)
      DomainEvents.subscribe(:event_b)

      payload_a = %{type: "a"}
      payload_b = %{type: "b"}

      DomainEvents.publish(:event_a, payload_a)
      DomainEvents.publish(:event_b, payload_b)

      assert_receive {:event_a, ^payload_a}, @receive_timeout
      assert_receive {:event_b, ^payload_b}, @receive_timeout
    end
  end

  describe "unsubscribe/1" do
    test "stops receiving events after unsubscribe" do
      DomainEvents.subscribe(:unsub_test)

      # Receive first event
      payload1 = %{count: 1}
      DomainEvents.publish(:unsub_test, payload1)
      assert_receive {:unsub_test, ^payload1}, @receive_timeout

      # Unsubscribe
      :ok = DomainEvents.unsubscribe(:unsub_test)

      # Publish second event - should not receive (use 0 timeout)
      payload2 = %{count: 2}
      DomainEvents.publish(:unsub_test, payload2)
      refute_receive {:unsub_test, ^payload2}, 0
    end
  end
end
