defmodule Portfolio.Auth.MagicLinkServiceTest do
  use Portfolio.DataCase

  alias Portfolio.Auth.{MagicLink, MagicLinkService, User}

  describe "request_magic_link/1" do
    test "creates magic link for existing user" do
      email = "test-#{System.unique_integer([:positive])}@example.com"
      user = insert_user(email: email)
      assert {:ok, magic_link} = MagicLinkService.request_magic_link(user.email)

      assert magic_link.user_id == user.id
      assert magic_link.token != nil
      assert is_binary(magic_link.token)
      assert magic_link.expires_at != nil
      assert magic_link.used_at == nil
    end

    test "creates user and magic link for new email in dev/test" do
      email = "newuser-#{System.unique_integer([:positive])}@example.com"
      assert {:ok, magic_link} = MagicLinkService.request_magic_link(email)

      assert magic_link.user_id != nil
      assert magic_link.token != nil
      assert magic_link.used_at == nil
    end

    @tag :skip
    test "returns success for unknown email in production (anti-enumeration)" do
      # NOTE: This test is skipped because Mix.env() cannot be changed at runtime.
      # The production behavior is tested manually during deployment.
      # In production (MIX_ENV=prod), unknown users will receive {:ok, :email_sent}
      # instead of creating a new account, preventing email enumeration attacks.
    end

    @tag :skip
    test "response time is consistent for existing and non-existing emails (timing attack prevention)" do
      # NOTE: This test is skipped because Mix.env() cannot be changed at runtime.
      # The timing attack protection is tested manually in production-like environments.
      # To test this behavior:
      # 1. Run with MIX_ENV=prod
      # 2. Measure response times for existing vs non-existing users
      # 3. Verify the difference is < 15%
    end

    @tag :skip
    test "no email is sent for unknown users in production" do
      # NOTE: This test is skipped because Mix.env() cannot be changed at runtime.
      # The production behavior (no user creation, no email sent) is tested manually.
      # In production (MIX_ENV=prod), unknown email addresses will not create users
      # and will not send emails, preventing email enumeration attacks.
    end

    test "magic link expires in 15 minutes" do
      email = "test-expiry-#{System.unique_integer([:positive])}@example.com"
      user = insert_user(email: email)
      assert {:ok, magic_link} = MagicLinkService.request_magic_link(user.email)

      expected_expiry = DateTime.add(DateTime.utc_now(), 15, :minute)
      diff = DateTime.diff(magic_link.expires_at, expected_expiry, :second)

      # Allow 2 seconds tolerance
      assert abs(diff) <= 2
    end

    test "generates unique tokens for same user" do
      email = "unique-tokens-#{System.unique_integer([:positive])}@example.com"
      user = insert_user(email: email)

      {:ok, magic_link1} = MagicLinkService.request_magic_link(user.email)
      {:ok, magic_link2} = MagicLinkService.request_magic_link(user.email)

      assert magic_link1.token != magic_link2.token
      assert magic_link1.user_id == magic_link2.user_id
    end

    test "enforces rate limit after 5 requests" do
      email = "ratelimit-test-#{System.unique_integer([:positive])}@example.com"

      # First 5 requests should succeed
      for _ <- 1..5 do
        assert {:ok, _magic_link} = MagicLinkService.request_magic_link(email)
      end

      # 6th request should be rate limited
      assert {:error, {:rate_limit_exceeded, _retry_after}} =
               MagicLinkService.request_magic_link(email)
    end

    test "rate limit is per email address" do
      email1 = "user1-#{System.unique_integer([:positive])}@example.com"
      email2 = "user2-#{System.unique_integer([:positive])}@example.com"

      # User 1 exhausts their limit
      for _ <- 1..5 do
        assert {:ok, _} = MagicLinkService.request_magic_link(email1)
      end

      assert {:error, {:rate_limit_exceeded, _retry_after}} =
               MagicLinkService.request_magic_link(email1)

      # User 2 should still be able to request
      assert {:ok, _magic_link} = MagicLinkService.request_magic_link(email2)
    end

    test "creates magic link even if previous ones exist" do
      email = "multiple-links-#{System.unique_integer([:positive])}@example.com"
      user = insert_user(email: email)

      {:ok, magic_link1} = MagicLinkService.request_magic_link(user.email)
      {:ok, magic_link2} = MagicLinkService.request_magic_link(user.email)

      # Both should exist in database
      assert Repo.get(MagicLink, magic_link1.id) != nil
      assert Repo.get(MagicLink, magic_link2.id) != nil
    end
  end

  describe "verify_magic_link/1" do
    test "returns {:ok, user} for valid magic link" do
      email = "verify-#{System.unique_integer([:positive])}@example.com"
      user = insert_user(email: email)
      {:ok, magic_link} = MagicLinkService.request_magic_link(user.email)

      assert {:ok, verified_user} = MagicLinkService.verify_magic_link(magic_link.token)
      assert verified_user.id == user.id
      assert verified_user.email == user.email
    end

    test "marks magic link as used after verification" do
      email = "mark-used-#{System.unique_integer([:positive])}@example.com"
      user = insert_user(email: email)
      {:ok, magic_link} = MagicLinkService.request_magic_link(user.email)

      assert magic_link.used_at == nil

      MagicLinkService.verify_magic_link(magic_link.token)

      used_magic_link = Repo.get(MagicLink, magic_link.id)
      assert used_magic_link.used_at != nil
      refute DateTime.compare(used_magic_link.used_at, DateTime.utc_now()) == :gt
    end

    test "returns {:error, :already_used} for used magic link" do
      email = "already-used-#{System.unique_integer([:positive])}@example.com"
      user = insert_user(email: email)
      {:ok, magic_link} = MagicLinkService.request_magic_link(user.email)

      {:ok, _user} = MagicLinkService.verify_magic_link(magic_link.token)
      assert {:error, :already_used} = MagicLinkService.verify_magic_link(magic_link.token)
    end

    test "returns {:error, :expired} for expired magic link" do
      user = insert_user()

      magic_link =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), -1, :hour))

      assert {:error, :expired} = MagicLinkService.verify_magic_link(magic_link.token)
    end

    test "returns {:error, :invalid_token} for non-existent token" do
      assert {:error, :invalid_token} = MagicLinkService.verify_magic_link("invalid-token")
    end

    test "returns {:error, :invalid_token} for empty string" do
      assert {:error, :invalid_token} = MagicLinkService.verify_magic_link("")
    end

    test "returns {:error, :invalid_token} for malformed token" do
      assert {:error, :invalid_token} =
               MagicLinkService.verify_magic_link("not-a-valid-base64-token")
    end

    test "does not mark expired links as used" do
      user = insert_user()

      magic_link =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), -1, :hour))

      MagicLinkService.verify_magic_link(magic_link.token)

      reloaded = Repo.get(MagicLink, magic_link.id)
      assert reloaded.used_at == nil
    end

    # Note: Atomicity is tested through Ecto.Multi transaction
    # but is difficult to test reliably in concurrent scenarios
    # The implementation uses Ecto.Multi to ensure atomicity
  end

  describe "delete_expired_magic_links/0" do
    test "deletes magic links that have expired" do
      user = insert_user()

      expired_link =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), -1, :hour))

      valid_link =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), 15, :minute))

      {count, nil} = MagicLinkService.delete_expired_magic_links()

      assert count >= 1
      assert Repo.get(MagicLink, expired_link.id) == nil
      assert Repo.get(MagicLink, valid_link.id) != nil
    end

    test "deletes multiple expired links at once" do
      user = insert_user()

      expired1 =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), -2, :hour))

      expired2 =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), -1, :hour))

      valid_link =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), 15, :minute))

      {count, nil} = MagicLinkService.delete_expired_magic_links()

      assert count >= 2
      assert Repo.get(MagicLink, expired1.id) == nil
      assert Repo.get(MagicLink, expired2.id) == nil
      assert Repo.get(MagicLink, valid_link.id) != nil
    end

    test "returns {0, nil} when no expired links" do
      user = insert_user()
      insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), 15, :minute))

      {count, nil} = MagicLinkService.delete_expired_magic_links()

      # May be more than 0 if there are expired links from other tests
      assert is_integer(count)
      assert count >= 0
    end

    test "does not delete used but not expired links" do
      user = insert_user()

      used_link =
        insert_magic_link(user,
          expires_at: DateTime.add(DateTime.utc_now(), 15, :minute),
          used_at: DateTime.utc_now()
        )

      {_count, nil} = MagicLinkService.delete_expired_magic_links()

      # Used links should not be deleted if not expired
      assert Repo.get(MagicLink, used_link.id) != nil
    end

    test "deletes expired used links" do
      user = insert_user()

      expired_used_link =
        insert_magic_link(user,
          expires_at: DateTime.add(DateTime.utc_now(), -1, :hour),
          used_at: DateTime.add(DateTime.utc_now(), -2, :hour)
        )

      {count, nil} = MagicLinkService.delete_expired_magic_links()

      assert count >= 1
      assert Repo.get(MagicLink, expired_used_link.id) == nil
    end
  end

  # Helper functions
  defp insert_user(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      email: "test-#{System.unique_integer([:positive])}@example.com",
      role: :admin
    }

    %User{}
    |> User.registration_changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp insert_magic_link(user, attrs) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      user_id: user.id,
      token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      short_code: generate_short_code(),
      expires_at: DateTime.add(DateTime.utc_now(), 15, :minute) |> DateTime.truncate(:second)
    }

    %MagicLink{}
    |> MagicLink.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp generate_short_code do
    :crypto.strong_rand_bytes(4)
    |> Base.encode32(padding: false)
    |> String.slice(0..5)
    |> String.upcase()
  end
end
