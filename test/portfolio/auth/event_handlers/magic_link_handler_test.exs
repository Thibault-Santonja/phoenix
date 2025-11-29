defmodule Portfolio.Auth.EventHandlers.MagicLinkHandlerTest do
  use ExUnit.Case, async: true

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

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "init/1" do
    test "initializes with empty state" do
      assert {:ok, %{}} = MagicLinkHandler.init([])
    end
  end

  describe "handle_info/2 - magic_link_requested" do
    test "handles MagicLinkRequested event" do
      # Note: token is intentionally NOT included in the event for security reasons
      # (prevents accidental logging of sensitive authentication tokens)
      event = %MagicLinkRequested{
        magic_link_id: Ecto.UUID.generate(),
        email: "test@example.com",
        short_code: "ABC123",
        requested_at: DateTime.utc_now(),
        expires_at: DateTime.utc_now() |> DateTime.add(900)
      }

      state = %{}

      assert {:noreply, ^state} =
               MagicLinkHandler.handle_info({:magic_link_requested, event}, state)
    end

    test "preserves state after handling event" do
      event = %MagicLinkRequested{
        magic_link_id: Ecto.UUID.generate(),
        email: "user@example.com",
        short_code: "XYZ789",
        requested_at: DateTime.utc_now(),
        expires_at: DateTime.utc_now() |> DateTime.add(900)
      }

      initial_state = %{some_key: "some_value"}

      assert {:noreply, ^initial_state} =
               MagicLinkHandler.handle_info({:magic_link_requested, event}, initial_state)
    end
  end

  describe "handle_info/2 - magic_link_verified" do
    test "handles MagicLinkVerified event" do
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

    test "preserves state after handling verified event" do
      event = %MagicLinkVerified{
        magic_link_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        email: "user@example.com",
        verified_at: DateTime.utc_now()
      }

      initial_state = %{counter: 5}

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

    test "handles random messages without crashing" do
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
end
