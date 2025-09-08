defmodule Portfolio.Auth.DomainEventsTest do
  use Portfolio.DataCase, async: false

  alias Portfolio.Auth
  alias Portfolio.DomainEvents
  alias Portfolio.Auth.Events.{MagicLinkRequested, MagicLinkVerified}

  setup do
    # Subscribe to events before each test
    DomainEvents.subscribe(:magic_link_requested)
    DomainEvents.subscribe(:magic_link_verified)
    :ok
  end

  describe "request_magic_link/1" do
    test "publishes MagicLinkRequested event when magic link is requested" do
      email = "test@example.com"

      {:ok, magic_link} = Auth.request_magic_link(email)

      # Assert event was published
      assert_receive {:magic_link_requested, %MagicLinkRequested{} = event}, 100

      # Verify event data
      assert event.magic_link_id == magic_link.id
      assert event.email == email
      assert event.token == magic_link.token
      assert %DateTime{} = event.requested_at
      assert %DateTime{} = event.expires_at
    end

    test "event contains correct expiration time" do
      email = "test2@example.com"

      {:ok, _magic_link} = Auth.request_magic_link(email)

      assert_receive {:magic_link_requested, %MagicLinkRequested{} = event}, 100

      # Magic link should expire in ~15 minutes
      diff = DateTime.diff(event.expires_at, event.requested_at, :minute)
      assert diff >= 14 and diff <= 16
    end
  end

  describe "verify_magic_link/1" do
    test "publishes MagicLinkVerified event when magic link is verified" do
      email = "verified@example.com"
      {:ok, magic_link} = Auth.request_magic_link(email)

      # Clear the requested event from mailbox
      assert_receive {:magic_link_requested, _}, 100

      # Verify the magic link
      {:ok, user} = Auth.verify_magic_link(magic_link.token)

      # Assert verified event was published
      assert_receive {:magic_link_verified, %MagicLinkVerified{} = event}, 100

      # Verify event data
      assert event.magic_link_id == magic_link.id
      assert event.user_id == user.id
      assert event.email == email
      assert %DateTime{} = event.verified_at
    end

    test "does not publish event if magic link is invalid" do
      {:error, :invalid_token} = Auth.verify_magic_link("invalid_token")

      # Should not receive verified event
      refute_receive {:magic_link_verified, _}, 100
    end

    test "does not publish event if magic link is expired" do
      email = "expired@example.com"
      {:ok, magic_link} = Auth.request_magic_link(email)

      # Clear requested event
      assert_receive {:magic_link_requested, _}, 100

      # Manually expire the magic link
      expired_time =
        DateTime.utc_now()
        |> DateTime.add(-20, :minute)
        |> DateTime.truncate(:second)

      magic_link
      |> Ecto.Changeset.change(%{expires_at: expired_time})
      |> Portfolio.Repo.update!()

      # Try to verify expired link
      {:error, :expired} = Auth.verify_magic_link(magic_link.token)

      # Should not receive verified event
      refute_receive {:magic_link_verified, _}, 100
    end

    test "does not publish event if magic link is already used" do
      email = "used@example.com"
      {:ok, magic_link} = Auth.request_magic_link(email)

      # Clear requested event
      assert_receive {:magic_link_requested, _}, 100

      # Verify once
      {:ok, _user} = Auth.verify_magic_link(magic_link.token)
      assert_receive {:magic_link_verified, _}, 100

      # Try to verify again
      {:error, :already_used} = Auth.verify_magic_link(magic_link.token)

      # Should not receive second verified event
      refute_receive {:magic_link_verified, _}, 100
    end
  end
end
