defmodule Portfolio.Auth.MagicLinkVerificationTest do
  @moduledoc """
  Tests for magic link verification error handling and telemetry.

  Covers edge cases and error conditions during magic link verification.
  """
  use Portfolio.DataCase

  alias Portfolio.Auth.{MagicLink, MagicLinkService, User}

  describe "verify_magic_link/1 error handling" do
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

    test "returns {:error, :expired} for expired magic link" do
      user = insert_user()

      magic_link =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), -1, :hour))

      assert {:error, :expired} = MagicLinkService.verify_magic_link(magic_link.token)
    end

    test "returns {:error, :already_used} for used magic link" do
      email = "already-used-#{System.unique_integer([:positive])}@example.com"
      user = insert_user(email: email)
      {:ok, magic_link} = MagicLinkService.request_magic_link(user.email)

      # First verification succeeds
      {:ok, _user} = MagicLinkService.verify_magic_link(magic_link.token)

      # Second verification fails
      assert {:error, :already_used} = MagicLinkService.verify_magic_link(magic_link.token)
    end

    test "does not mark expired links as used" do
      user = insert_user()

      magic_link =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), -1, :hour))

      MagicLinkService.verify_magic_link(magic_link.token)

      reloaded = Repo.get(MagicLink, magic_link.id)
      assert reloaded.used_at == nil
    end
  end

  describe "verify_magic_link/1 telemetry" do
    setup do
      test_pid = self()

      :telemetry.attach(
        "test-magic-link-verification",
        [:portfolio, :auth, :magic_link, :verified],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-magic-link-verification")
      end)

      :ok
    end

    test "emits telemetry on successful verification" do
      user = insert_user()
      {:ok, magic_link} = MagicLinkService.request_magic_link(user.email)

      {:ok, _verified_user} = MagicLinkService.verify_magic_link(magic_link.token)

      assert_received {:telemetry, [:portfolio, :auth, :magic_link, :verified], measurements,
                       metadata}

      assert is_integer(measurements.duration)
      assert measurements.duration > 0
      assert metadata.result == :ok
    end

    test "emits telemetry on invalid token" do
      MagicLinkService.verify_magic_link("invalid-token")

      assert_received {:telemetry, [:portfolio, :auth, :magic_link, :verified], measurements,
                       metadata}

      assert is_integer(measurements.duration)
      assert metadata.result == :error
    end

    test "emits telemetry on expired link" do
      user = insert_user()

      magic_link =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), -1, :hour))

      MagicLinkService.verify_magic_link(magic_link.token)

      assert_received {:telemetry, [:portfolio, :auth, :magic_link, :verified], measurements,
                       metadata}

      assert is_integer(measurements.duration)
      assert metadata.result == :error
    end

    test "emits telemetry on already used link" do
      user = insert_user()
      {:ok, magic_link} = MagicLinkService.request_magic_link(user.email)

      # Use the link once
      {:ok, _user} = MagicLinkService.verify_magic_link(magic_link.token)

      # Clear mailbox
      receive do
        {:telemetry, _, _, _} -> :ok
      end

      # Try to use it again
      {:error, :already_used} = MagicLinkService.verify_magic_link(magic_link.token)

      assert_received {:telemetry, [:portfolio, :auth, :magic_link, :verified], measurements,
                       metadata}

      assert is_integer(measurements.duration)
      assert metadata.result == :error
    end

    test "telemetry duration is consistent for valid and invalid tokens (timing attack prevention)" do
      user = insert_user()
      {:ok, magic_link} = MagicLinkService.request_magic_link(user.email)

      # Measure valid token verification time
      {:ok, _user} = MagicLinkService.verify_magic_link(magic_link.token)

      assert_received {:telemetry, _, valid_measurements, _}
      valid_duration = valid_measurements.duration

      # Measure invalid token verification time
      MagicLinkService.verify_magic_link("invalid-token")

      assert_received {:telemetry, _, invalid_measurements, _}
      invalid_duration = invalid_measurements.duration

      # Both should be in the same order of magnitude
      # Allow for reasonable variation but ensure constant-time behavior
      assert valid_duration > 0
      assert invalid_duration > 0

      # Durations should not differ by more than 10x (indicates constant-time work)
      ratio = max(valid_duration, invalid_duration) / min(valid_duration, invalid_duration)
      assert ratio < 10, "Duration ratio #{ratio} indicates timing attack vulnerability"
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
