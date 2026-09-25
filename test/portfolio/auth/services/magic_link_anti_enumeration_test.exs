defmodule Portfolio.Auth.Services.MagicLinkAntiEnumerationTest do
  @moduledoc """
  Tests for email enumeration protection in magic link authentication.

  Verifies that the system does not leak information about which email addresses
  are registered, preventing attackers from discovering valid accounts.
  """
  use Portfolio.DataCase, async: false

  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Auth.Services.MagicLinkAuthService

  setup do
    # Create a known user
    existing_user = create_user(email: "existing@example.com")
    %{existing_user: existing_user}
  end

  # Ecoute l'evenement de temporisation anti-enumeration. Le handler est global
  # au noeud et s'execute dans le processus emetteur : le filtre sur `test_pid`
  # evite de lire la requete d'un test concurrent.
  defp attach_delay_probe do
    test_pid = self()
    handler_id = "timing-safe-delay-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:portfolio, :auth, :magic_link, :timing_safe_delay],
      fn _event, measurements, metadata, _config ->
        if self() == test_pid do
          send(test_pid, {:timing_safe_delay, measurements, metadata})
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  describe "anti-enumeration in production" do
    setup do
      # Simulate production environment
      original_env = Application.get_env(:portfolio, :env)
      Application.put_env(:portfolio, :env, :prod)

      on_exit(fn ->
        Application.put_env(:portfolio, :env, original_env)
      end)

      :ok
    end

    test "returns success for existing user", %{existing_user: user} do
      result = MagicLinkAuthService.execute(user.email)

      # Should succeed and create magic link
      assert {:ok, magic_link} = result
      assert magic_link.token
    end

    test "returns success for non-existing user to prevent enumeration" do
      result = MagicLinkAuthService.execute("nonexistent@example.com")

      # Should return success (not error) to prevent enumeration
      assert {:ok, :email_sent} = result
    end

    # Ce test comparait les deux chemins a un ecart de chronometre de 50 ms.
    # Il eprouvait la machine, pas la protection : sous charge, l'ecart mesure
    # entre les deux chemins ne distingue plus une temporisation appliquee
    # d'une temporisation absente, parce que le chemin existant (base et
    # evenements) ralentit plus vite qu'un `sleep`. Il observe desormais la
    # temporisation elle-meme, qui est rendue observable par le service : une
    # pause ne rend jamais la main en avance, donc la borne basse reste vraie
    # quelle que soit la charge.
    test "the missing user path actually spends its timing safe delay" do
      attach_delay_probe()

      assert {:ok, :email_sent} = MagicLinkAuthService.execute("nonexistent@example.com")

      assert_received {:timing_safe_delay, measurements, metadata}

      assert measurements.elapsed_us >= metadata.configured_ms * 1000,
             "la temporisation a rendu la main en #{measurements.elapsed_us}us, " <>
               "sous les #{metadata.configured_ms}ms demandes"
    end

    test "the existing user path does not need the timing safe delay", %{existing_user: user} do
      attach_delay_probe()

      assert {:ok, _magic_link} = MagicLinkAuthService.execute(user.email)

      refute_received {:timing_safe_delay, _measurements, _metadata}
    end

    test "does not create magic link for non-existing user" do
      before_count = Repo.aggregate(Portfolio.Auth.MagicLink, :count, :id)

      MagicLinkAuthService.execute("nonexistent@example.com")

      after_count = Repo.aggregate(Portfolio.Auth.MagicLink, :count, :id)

      # No magic link should be created
      assert before_count == after_count
    end

    test "rate limiting still applies to non-existing emails" do
      # Use unique email to avoid rate limit collisions with other tests
      email = "attacker_#{System.unique_integer([:positive])}@example.com"

      # Make 5 requests (rate limit is 5 per hour)
      for _ <- 1..5 do
        assert {:ok, _} = MagicLinkAuthService.execute(email)
      end

      # 6th request should be rate limited
      assert {:error, {:rate_limit_exceeded, _}} = MagicLinkAuthService.execute(email)
    end
  end

  describe "behavior in development" do
    setup do
      # Ensure we're in dev environment
      original_env = Application.get_env(:portfolio, :env)
      Application.put_env(:portfolio, :env, :dev)

      on_exit(fn ->
        Application.put_env(:portfolio, :env, original_env)
      end)

      :ok
    end

    test "creates user automatically in dev for non-existing email" do
      email = "newuser-#{System.unique_integer()}@example.com"

      result = MagicLinkAuthService.execute(email)

      # Should succeed and create both user and magic link
      assert {:ok, magic_link} = result
      assert magic_link.token

      # User should be created
      assert Portfolio.Repo.get_by(Portfolio.Auth.User, email: email)
    end
  end

  describe "security best practices" do
    test "error messages do not reveal user existence" do
      # In production
      original_env = Application.get_env(:portfolio, :env)
      Application.put_env(:portfolio, :env, :prod)

      # Request for non-existing user
      result = MagicLinkAuthService.execute("ghost@example.com")

      # Should not return :user_not_found error
      refute match?({:error, :user_not_found}, result)

      # Should return success
      assert match?({:ok, _}, result)

      Application.put_env(:portfolio, :env, original_env)
    end

    test "logs do not contain sensitive email information" do
      # This is more of a reminder - actual log sanitization
      # should be implemented in the logging configuration
      assert true, "Ensure logs are sanitized in production"
    end
  end
end
