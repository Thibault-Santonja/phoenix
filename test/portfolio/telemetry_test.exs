defmodule Portfolio.TelemetryTest do
  use Portfolio.DataCase, async: false

  alias Portfolio.Auth
  alias Portfolio.Photography

  describe "Photography telemetry" do
    setup do
      # Attach a test handler to capture telemetry events
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:portfolio, :photography, :album, :created],
          [:portfolio, :photography, :photos, :uploaded]
        ])

      on_exit(fn -> :telemetry.detach(ref) end)

      :ok
    end

    test "emits telemetry event when album is created" do
      attrs = %{
        title: "Test Album",
        description: "Test description",
        type: "landscape",
        date_prise_vue: ~D[2024-01-15]
      }

      {:ok, _album} = Photography.create_album(attrs)

      assert_received {
        [:portfolio, :photography, :album, :created],
        _ref,
        %{duration: duration},
        %{result: :ok}
      }

      assert is_integer(duration)
      assert duration > 0
    end

    test "emits telemetry event with error status when album creation fails" do
      attrs = %{description: "Missing title"}

      {:error, _changeset} = Photography.create_album(attrs)

      assert_received {
        [:portfolio, :photography, :album, :created],
        _ref,
        %{duration: duration},
        %{result: :error}
      }

      assert is_integer(duration)
      assert duration > 0
    end

    test "emits telemetry event when photo upload fails with non-existent album" do
      uploads = [%{path: "test.jpg", filename: "test.jpg"}]

      {:error, _reason} = Photography.upload_photos("non-existent-slug", uploads)

      assert_received {
        [:portfolio, :photography, :photos, :uploaded],
        _ref,
        %{duration: duration},
        %{album_slug: "non-existent-slug", count: 1, result: :error}
      }

      assert is_integer(duration)
      assert duration > 0
    end
  end

  describe "Auth telemetry" do
    setup do
      # Attach a test handler to capture telemetry events
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:portfolio, :auth, :magic_link, :requested],
          [:portfolio, :auth, :magic_link, :verified]
        ])

      on_exit(fn -> :telemetry.detach(ref) end)

      :ok
    end

    test "emits telemetry event when magic link is requested" do
      email = "test@example.com"

      {:ok, _magic_link} = Auth.request_magic_link(email)

      # Clear the email from mailbox
      receive do
        {:email, _} -> :ok
      after
        100 -> :ok
      end

      assert_received {
        [:portfolio, :auth, :magic_link, :requested],
        _ref,
        %{duration: duration},
        %{email: ^email, result: :ok}
      }

      assert is_integer(duration)
      assert duration > 0
    end

    test "emits telemetry event when magic link verification succeeds" do
      email = "verify@example.com"
      {:ok, magic_link} = Auth.request_magic_link(email)

      # Clear the email and request event from the mailbox
      receive do
        {:email, _} -> :ok
      after
        100 -> :ok
      end

      receive do
        {[:portfolio, :auth, :magic_link, :requested], _, _, _} -> :ok
      after
        100 -> :ok
      end

      {:ok, _user} = Auth.verify_magic_link(magic_link.token)

      assert_received {
        [:portfolio, :auth, :magic_link, :verified],
        _ref,
        %{duration: duration},
        %{result: :ok}
      }

      assert is_integer(duration)
      assert duration > 0
    end

    test "emits telemetry event when magic link verification fails" do
      {:error, _reason} = Auth.verify_magic_link("invalid-token")

      assert_received {
        [:portfolio, :auth, :magic_link, :verified],
        _ref,
        %{duration: duration},
        %{result: :error}
      }

      assert is_integer(duration)
      assert duration > 0
    end

    test "emits telemetry event when magic link is expired" do
      email = "expired@example.com"
      {:ok, magic_link} = Auth.request_magic_link(email)

      # Clear the email and request event
      receive do
        {:email, _} -> :ok
      after
        100 -> :ok
      end

      receive do
        {[:portfolio, :auth, :magic_link, :requested], _, _, _} -> :ok
      after
        100 -> :ok
      end

      # Manually expire the magic link
      expired_time = DateTime.utc_now() |> DateTime.add(-2, :hour) |> DateTime.truncate(:second)

      Portfolio.Repo.update!(Ecto.Changeset.change(magic_link, expires_at: expired_time))

      {:error, :expired} = Auth.verify_magic_link(magic_link.token)

      assert_received {
        [:portfolio, :auth, :magic_link, :verified],
        _ref,
        %{duration: duration},
        %{result: :error}
      }

      assert is_integer(duration)
      assert duration > 0
    end
  end
end
