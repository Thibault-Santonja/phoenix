defmodule Portfolio.Auth.EventHandlers.MagicLinkHandlerTest do
  @moduledoc """
  Tests for MagicLinkHandler GenServer.
  """
  use Portfolio.DataCase, async: false

  alias Portfolio.Auth.EventHandlers.MagicLinkHandler
  alias Portfolio.Auth.Events.{MagicLinkRequested, MagicLinkVerified}

  describe "start_link/1" do
    test "starts the GenServer successfully" do
      # Stop existing handler if running
      if pid = Process.whereis(MagicLinkHandler) do
        GenServer.stop(pid)
      end

      assert {:ok, pid} = MagicLinkHandler.start_link([])
      assert is_pid(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "init/1" do
    test "initializes with empty state" do
      # Stop existing handler if running
      if pid = Process.whereis(MagicLinkHandler) do
        GenServer.stop(pid)
      end

      {:ok, pid} = MagicLinkHandler.start_link([])

      # Handler should be running
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "handle_info/2 - magic_link_requested event" do
    test "handles MagicLinkRequested event successfully" do
      event = %MagicLinkRequested{
        magic_link_id: Ecto.UUID.generate(),
        email: "test@example.com",
        short_code: "ABC123",
        requested_at: DateTime.utc_now(),
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      state = %{}

      assert {:noreply, ^state} =
               MagicLinkHandler.handle_info({:magic_link_requested, event}, state)
    end

    test "preserves state after handling event" do
      event = %MagicLinkRequested{
        magic_link_id: Ecto.UUID.generate(),
        email: "test@example.com",
        short_code: "DEF456",
        requested_at: DateTime.utc_now(),
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      initial_state = %{counter: 5}

      assert {:noreply, ^initial_state} =
               MagicLinkHandler.handle_info({:magic_link_requested, event}, initial_state)
    end
  end

  describe "handle_info/2 - magic_link_verified event" do
    test "handles MagicLinkVerified event successfully" do
      event = %MagicLinkVerified{
        magic_link_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        email: "verified@example.com",
        verified_at: DateTime.utc_now()
      }

      state = %{}

      assert {:noreply, ^state} =
               MagicLinkHandler.handle_info({:magic_link_verified, event}, state)
    end

    test "preserves state after verification event" do
      event = %MagicLinkVerified{
        magic_link_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        email: "verified@example.com",
        verified_at: DateTime.utc_now()
      }

      initial_state = %{data: "test"}

      assert {:noreply, ^initial_state} =
               MagicLinkHandler.handle_info({:magic_link_verified, event}, initial_state)
    end
  end

  describe "handle_info/2 - unexpected messages" do
    test "handles unexpected messages gracefully" do
      state = %{}

      assert {:noreply, ^state} =
               MagicLinkHandler.handle_info({:unknown_event, %{}}, state)
    end

    test "handles random atom messages" do
      state = %{data: "test"}

      assert {:noreply, ^state} =
               MagicLinkHandler.handle_info(:random_atom, state)
    end

    test "handles nil message" do
      state = %{}

      assert {:noreply, ^state} =
               MagicLinkHandler.handle_info(nil, state)
    end
  end

  describe "event processing" do
    test "handles multiple events sequentially" do
      state = %{}

      event1 = %MagicLinkRequested{
        magic_link_id: Ecto.UUID.generate(),
        email: "user1@example.com",
        short_code: "SEQ123",
        requested_at: DateTime.utc_now(),
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      event2 = %MagicLinkVerified{
        magic_link_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        email: "user1@example.com",
        verified_at: DateTime.utc_now()
      }

      {:noreply, state} = MagicLinkHandler.handle_info({:magic_link_requested, event1}, state)

      assert {:noreply, ^state} =
               MagicLinkHandler.handle_info({:magic_link_verified, event2}, state)
    end
  end
end
