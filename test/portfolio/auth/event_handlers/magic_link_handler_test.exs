defmodule Portfolio.Auth.EventHandlers.MagicLinkHandlerTest do
  use ExUnit.Case, async: true

  alias Portfolio.Auth.EventHandlers.MagicLinkHandler
  alias Portfolio.Auth.Events.{MagicLinkRequested, MagicLinkVerified}

  describe "handle_info/2 with :magic_link_requested event" do
    test "processes magic link requested event and logs" do
      event = %MagicLinkRequested{
        magic_link_id: Ecto.UUID.generate(),
        email: "test@example.com",
        token: "test_token_hash",
        short_code: "ABC123",
        requested_at: DateTime.utc_now(),
        expires_at: DateTime.utc_now() |> DateTime.add(900, :second)
      }

      # Send event to handler
      assert {:noreply, %{}} =
               MagicLinkHandler.handle_info({:magic_link_requested, event}, %{})
    end
  end

  describe "handle_info/2 with :magic_link_verified event" do
    test "processes magic link verified event and logs" do
      event = %MagicLinkVerified{
        magic_link_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        email: "test@example.com",
        verified_at: DateTime.utc_now()
      }

      # Send event to handler
      assert {:noreply, %{}} =
               MagicLinkHandler.handle_info({:magic_link_verified, event}, %{})
    end
  end

  describe "handle_info/2 with unexpected messages" do
    test "handles unexpected messages gracefully" do
      assert {:noreply, %{}} = MagicLinkHandler.handle_info({:unexpected, :message}, %{})
    end
  end
end
