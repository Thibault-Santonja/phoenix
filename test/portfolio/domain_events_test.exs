defmodule Portfolio.DomainEventsTest do
  use ExUnit.Case, async: true

  alias Portfolio.DomainEvents

  describe "publish/2 and subscribe/1" do
    test "publishes events to subscribed processes" do
      # Subscribe to a test event
      :ok = DomainEvents.subscribe(:test_event)

      # Publish an event
      payload = %{id: "123", message: "test"}
      :ok = DomainEvents.publish(:test_event, payload)

      # Assert the process receives the event
      assert_receive {:test_event, ^payload}, 100
    end

    test "does not receive events without subscription" do
      # Don't subscribe, just publish
      payload = %{id: "456", message: "test2"}
      :ok = DomainEvents.publish(:unsubscribed_event, payload)

      # Should not receive any message
      refute_receive {:unsubscribed_event, _}, 100
    end

    test "multiple subscribers receive the same event" do
      # Create a test process that subscribes
      parent = self()

      subscriber1 =
        spawn_link(fn ->
          DomainEvents.subscribe(:multi_event)

          receive do
            {:multi_event, payload} ->
              send(parent, {:subscriber1, payload})
          end
        end)

      subscriber2 =
        spawn_link(fn ->
          DomainEvents.subscribe(:multi_event)

          receive do
            {:multi_event, payload} ->
              send(parent, {:subscriber2, payload})
          end
        end)

      # Give subscribers time to subscribe
      Process.sleep(10)

      # Publish event
      payload = %{test: "data"}
      DomainEvents.publish(:multi_event, payload)

      # Both subscribers should receive
      assert_receive {:subscriber1, ^payload}, 100
      assert_receive {:subscriber2, ^payload}, 100

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

      assert_receive {:event_a, ^payload_a}, 100
      assert_receive {:event_b, ^payload_b}, 100
    end
  end

  describe "unsubscribe/1" do
    test "stops receiving events after unsubscribe" do
      DomainEvents.subscribe(:unsub_test)

      # Receive first event
      payload1 = %{count: 1}
      DomainEvents.publish(:unsub_test, payload1)
      assert_receive {:unsub_test, ^payload1}, 100

      # Unsubscribe
      :ok = DomainEvents.unsubscribe(:unsub_test)

      # Publish second event - should not receive
      payload2 = %{count: 2}
      DomainEvents.publish(:unsub_test, payload2)
      refute_receive {:unsub_test, ^payload2}, 100
    end
  end
end
