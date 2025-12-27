defmodule Portfolio.Auth.Services.MagicLinkAuthServiceTest do
  use Portfolio.DataCase, async: false

  import Swoosh.TestAssertions

  alias Portfolio.Auth.User
  alias Portfolio.Repo
  alias Portfolio.Auth.Services.MagicLinkAuthService

  setup do
    # Reset rate limiter before each test
    Portfolio.RateLimiter.reset_all()

    :ok
  end

  describe "execute/2" do
    test "creates magic link for existing user" do
      # Create a user first
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: "existing@example.com", role: "admin"})
        |> Repo.insert()

      result = MagicLinkAuthService.execute(user.email)

      assert {:ok, magic_link} = result
      assert magic_link.user_id == user.id
      assert magic_link.token != nil
      assert magic_link.short_code != nil
      assert String.length(magic_link.short_code) == 6
    end

    test "sends email with magic link" do
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: "email_test@example.com", role: "admin"})
        |> Repo.insert()

      {:ok, _magic_link} = MagicLinkAuthService.execute(user.email)

      # Email is sent with name from user (or email as fallback)
      assert_email_sent(fn email ->
        assert email.to == [{user.email, user.email}]
      end)
    end

    test "magic link has correct expiration" do
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: "expiry@example.com", role: "admin"})
        |> Repo.insert()

      {:ok, magic_link} = MagicLinkAuthService.execute(user.email)

      # Should expire in ~15 minutes (default TTL)
      now = DateTime.utc_now()
      diff_seconds = DateTime.diff(magic_link.expires_at, now)

      # Allow 1 minute tolerance
      assert diff_seconds >= 14 * 60
      assert diff_seconds <= 16 * 60
    end

    test "rate limits requests per email" do
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: "ratelimit@example.com", role: "admin"})
        |> Repo.insert()

      # Make 5 requests (the limit)
      for _ <- 1..5 do
        {:ok, _} = MagicLinkAuthService.execute(user.email)
      end

      # 6th request should be rate limited
      result = MagicLinkAuthService.execute(user.email)

      assert {:error, {:rate_limit_exceeded, _retry_after}} = result
    end

    test "bypass_rate_limit option skips rate limiting" do
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: "bypass@example.com", role: "admin"})
        |> Repo.insert()

      # Exhaust rate limit
      for _ <- 1..5 do
        {:ok, _} = MagicLinkAuthService.execute(user.email)
      end

      # Should succeed with bypass
      result = MagicLinkAuthService.execute(user.email, bypass_rate_limit: true)

      assert {:ok, _magic_link} = result
    end

    test "returns :email_sent for non-existing user in production mode" do
      # Simulate production environment
      Application.put_env(:portfolio, :env, :prod)

      on_exit(fn ->
        Application.delete_env(:portfolio, :env)
      end)

      result = MagicLinkAuthService.execute("nonexistent@example.com")

      # Should return success to prevent email enumeration
      assert {:ok, :email_sent} = result
    end

    test "creates user in dev/test mode for non-existing email" do
      # Ensure we're not in production mode
      Application.delete_env(:portfolio, :env)

      email = "newuser_#{System.unique_integer([:positive])}@example.com"

      result = MagicLinkAuthService.execute(email)

      assert {:ok, magic_link} = result
      assert magic_link.token != nil

      # User should have been created
      user = Repo.get_by(User, email: email)
      assert user != nil
    end

    test "emits telemetry event" do
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: "telemetry@example.com", role: "admin"})
        |> Repo.insert()

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:portfolio, :auth, :magic_link, :requested]
        ])

      MagicLinkAuthService.execute(user.email)

      assert_received {[:portfolio, :auth, :magic_link, :requested], ^ref, _measurements,
                       %{email: _}}
    end

    test "generates unique tokens for each request" do
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: "unique@example.com", role: "admin"})
        |> Repo.insert()

      {:ok, link1} = MagicLinkAuthService.execute(user.email)
      {:ok, link2} = MagicLinkAuthService.execute(user.email)

      assert link1.token != link2.token
      assert link1.short_code != link2.short_code
    end
  end
end
