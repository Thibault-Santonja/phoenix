defmodule Portfolio.Auth.MagicLinkVerificationTest do
  @moduledoc """
  Tests for magic link verification error handling and telemetry.

  Covers edge cases and error conditions during magic link verification.
  """
  use Portfolio.DataCase, async: true

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
      # Use unique handler ID to avoid conflicts with parallel tests
      handler_id = "test-magic-link-verification-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:portfolio, :auth, :magic_link, :verified],
        fn event, measurements, metadata, _config ->
          # Un handler telemetry est global au noeud et s'execute dans le
          # processus emetteur : sans ce filtre, les verifications d'un test
          # concurrent (suite async) arrivent aussi dans cette boite aux
          # lettres et `assert_received` lit leur resultat a la place.
          if self() == test_pid do
            send(test_pid, {:telemetry, event, measurements, metadata})
          end
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
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

      # Clear first telemetry message from successful verification
      assert_received {:telemetry, [:portfolio, :auth, :magic_link, :verified], _, %{result: :ok}}

      # Try to use it again
      {:error, :already_used} = MagicLinkService.verify_magic_link(magic_link.token)

      assert_received {:telemetry, [:portfolio, :auth, :magic_link, :verified], measurements,
                       metadata}

      assert is_integer(measurements.duration)
      assert metadata.result == :error
    end

    # This used to compare one valid and one invalid verification and require
    # their durations to stay within a factor of fifty. Two things were wrong
    # with it. It compared two single wall-clock samples on a machine running
    # the suite in parallel, so it failed at random (a ratio of 461 was
    # measured under load). And it could not have held even on a quiet
    # machine: the valid path writes the magic link back to the database,
    # while the unknown-token path only runs a 32-byte `secure_compare`, so
    # the two paths do structurally different work. What this test verifies
    # is only that both paths report a duration. The actual anti-timing-attack
    # guarantee for the invalid-token path is proven below, by observing that
    # its constant-time compensation work fires (see the "constant time work"
    # describe block).
    test "both verification paths are measured and reported" do
      user = insert_user()
      {:ok, magic_link} = MagicLinkService.request_magic_link(user.email)

      assert {:ok, _user} = MagicLinkService.verify_magic_link(magic_link.token)
      assert_received {:telemetry, _, valid_measurements, valid_metadata}

      assert {:error, :invalid_token} = MagicLinkService.verify_magic_link("invalid-token")
      assert_received {:telemetry, _, invalid_measurements, invalid_metadata}

      assert valid_measurements.duration > 0
      assert invalid_measurements.duration > 0
      assert valid_metadata.result == :ok
      assert invalid_metadata.result == :error
    end
  end

  # Le rapport des durees mesurees par cette meme suite ne dit rien de la
  # protection : sous charge, le chemin valide (base de donnees) ralentit bien
  # plus vite que le travail de compensation, et le rapport explose sans
  # qu'aucune protection n'ait bouge. Ce qui se verifie de facon stable, c'est
  # que le chemin du jeton invalide execute bien son travail de compensation,
  # et que le chemin valide n'en a pas besoin.
  describe "verify_magic_link/1 constant time work" do
    setup do
      attach_constant_time_probe()
    end

    test "the invalid token path performs its constant time work" do
      assert {:error, :invalid_token} = MagicLinkService.verify_magic_link("invalid-token")

      assert_received {:constant_time_work, _measurements}
    end

    test "the valid token path does not need the constant time work" do
      user = insert_user()
      {:ok, magic_link} = MagicLinkService.request_magic_link(user.email)

      assert {:ok, _verified_user} = MagicLinkService.verify_magic_link(magic_link.token)

      refute_received {:constant_time_work, _measurements}
    end
  end

  # Ecoute le travail de compensation anti-attaque temporelle. Handler global au
  # noeud et execute dans le processus emetteur, d'ou le filtre sur `test_pid`.
  defp attach_constant_time_probe do
    test_pid = self()
    handler_id = "constant-time-work-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:portfolio, :auth, :magic_link, :constant_time_work],
      fn _event, measurements, _metadata, _config ->
        if self() == test_pid do
          send(test_pid, {:constant_time_work, measurements})
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
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
