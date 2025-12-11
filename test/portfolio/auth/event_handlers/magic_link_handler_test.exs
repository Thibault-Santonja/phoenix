defmodule Portfolio.Auth.EventHandlers.MagicLinkHandlerTest do
  use ExUnit.Case, async: false

  alias Portfolio.Auth.EventHandlers.MagicLinkHandler
  alias Portfolio.Auth.Events.MagicLinkRequested
  alias Portfolio.Auth.Events.MagicLinkVerified
  alias Portfolio.DomainEvents

  describe "start_link/1" do
    test "starts the handler GenServer" do
      case GenServer.whereis(MagicLinkHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      assert {:ok, pid} = MagicLinkHandler.start_link([])
      assert is_pid(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "registers with module name" do
      case GenServer.whereis(MagicLinkHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = MagicLinkHandler.start_link([])

      assert GenServer.whereis(MagicLinkHandler) == pid

      GenServer.stop(pid)
    end
  end

  describe "handle_info/2 for magic_link_requested" do
    setup do
      case GenServer.whereis(MagicLinkHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = MagicLinkHandler.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, handler_pid: pid}
    end

    test "processes magic link requested event without crashing", %{handler_pid: pid} do
      event = %MagicLinkRequested{
        magic_link_id: "ml_123",
        email: "test@example.com",
        short_code: "ABC123",
        requested_at: DateTime.utc_now(),
        expires_at: DateTime.add(DateTime.utc_now(), 900, :second)
      }

      send(pid, {:magic_link_requested, event})
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "receives event through DomainEvents.publish", %{handler_pid: pid} do
      event = %MagicLinkRequested{
        magic_link_id: "ml_456",
        email: "user@domain.com",
        short_code: "DEF456",
        requested_at: DateTime.utc_now(),
        expires_at: DateTime.add(DateTime.utc_now(), 900, :second)
      }

      DomainEvents.publish(:magic_link_requested, event)
      Process.sleep(50)

      # Handler should still be alive after processing
      assert Process.alive?(pid)
    end

    test "handles multiple events in sequence", %{handler_pid: pid} do
      for i <- 1..5 do
        event = %MagicLinkRequested{
          magic_link_id: "ml_seq_#{i}",
          email: "user#{i}@example.com",
          short_code: "SEQ#{i}00",
          requested_at: DateTime.utc_now(),
          expires_at: DateTime.add(DateTime.utc_now(), 900, :second)
        }

        send(pid, {:magic_link_requested, event})
      end

      Process.sleep(100)
      assert Process.alive?(pid)
    end
  end

  describe "handle_info/2 for magic_link_verified" do
    setup do
      case GenServer.whereis(MagicLinkHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = MagicLinkHandler.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, handler_pid: pid}
    end

    test "processes magic link verified event without crashing", %{handler_pid: pid} do
      event = %MagicLinkVerified{
        magic_link_id: "ml_789",
        user_id: "user_123",
        email: "verified@example.com",
        verified_at: DateTime.utc_now()
      }

      send(pid, {:magic_link_verified, event})
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "receives event through DomainEvents.publish", %{handler_pid: pid} do
      event = %MagicLinkVerified{
        magic_link_id: "ml_abc",
        user_id: "user_xyz",
        email: "auth@example.com",
        verified_at: DateTime.utc_now()
      }

      DomainEvents.publish(:magic_link_verified, event)
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles multiple verification events", %{handler_pid: pid} do
      for i <- 1..3 do
        event = %MagicLinkVerified{
          magic_link_id: "ml_ver_#{i}",
          user_id: "user_ver_#{i}",
          email: "verified#{i}@example.com",
          verified_at: DateTime.utc_now()
        }

        send(pid, {:magic_link_verified, event})
      end

      Process.sleep(100)
      assert Process.alive?(pid)
    end
  end

  describe "handle_info/2 for unexpected messages" do
    setup do
      case GenServer.whereis(MagicLinkHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = MagicLinkHandler.start_link([])

      on_exit(fn ->
        case GenServer.whereis(MagicLinkHandler) do
          nil ->
            :ok

          p when is_pid(p) ->
            if Process.alive?(p), do: GenServer.stop(p, :normal, 100), else: :ok

          _ ->
            :ok
        end
      end)

      {:ok, handler_pid: pid}
    end

    test "handles unexpected tuple message gracefully", %{handler_pid: pid} do
      send(pid, {:unexpected_event, %{data: "test"}})
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles unexpected atom message gracefully", %{handler_pid: pid} do
      send(pid, :random_atom)
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles nil message gracefully", %{handler_pid: pid} do
      send(pid, nil)
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles string message gracefully", %{handler_pid: pid} do
      send(pid, "unexpected string")
      Process.sleep(100)

      assert Process.alive?(pid)
    end
  end

  describe "subscription behavior" do
    test "subscribes to magic_link_requested on init" do
      case GenServer.whereis(MagicLinkHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = MagicLinkHandler.start_link([])

      # Publish an event - handler should receive it
      event = %MagicLinkRequested{
        magic_link_id: "ml_sub_test",
        email: "sub@test.com",
        short_code: "SUB123",
        requested_at: DateTime.utc_now(),
        expires_at: DateTime.add(DateTime.utc_now(), 900, :second)
      }

      DomainEvents.publish(:magic_link_requested, event)
      Process.sleep(50)

      # Handler processed event and is still alive
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "subscribes to magic_link_verified on init" do
      case GenServer.whereis(MagicLinkHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = MagicLinkHandler.start_link([])

      event = %MagicLinkVerified{
        magic_link_id: "ml_sub_ver",
        user_id: "user_sub",
        email: "subver@test.com",
        verified_at: DateTime.utc_now()
      }

      DomainEvents.publish(:magic_link_verified, event)
      Process.sleep(50)

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end
end
