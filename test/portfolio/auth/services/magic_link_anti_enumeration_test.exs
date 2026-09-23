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

    test "le chemin d'une adresse inconnue passe par le delai anti-enumeration" do
      # Comparer deux temps murs ne mesure rien d'utile ici : le delai reel
      # vaut trois millisecondes, soit moins que le bruit d'ordonnancement
      # d'une suite qui tourne sur vingt processus. Un tel test echoue au
      # hasard sans jamais detecter la disparition du delai.
      #
      # On verifie donc la seule chose qui compte et qui soit observable : le
      # chemin « adresse inconnue » attend bien. Le delai est rendu mesurable
      # pour la duree du test, et la borne est unilaterale, donc insensible a
      # la charge : le bruit ne peut qu'allonger la mesure.
      Application.put_env(:portfolio, :magic_link_timing_delay_ms, 150)
      on_exit(fn -> Application.delete_env(:portfolio, :magic_link_timing_delay_ms) end)

      {duree, resultat} =
        :timer.tc(fn -> MagicLinkAuthService.execute("nonexistent@example.com") end)

      assert {:ok, :email_sent} = resultat

      assert duree >= 150_000,
             "Le delai anti-enumeration n'a pas ete applique : #{duree} microsecondes"
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
