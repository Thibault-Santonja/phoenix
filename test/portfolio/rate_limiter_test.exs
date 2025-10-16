defmodule Portfolio.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Portfolio.RateLimiter

  setup do
    # Reset tous les rate limits avant chaque test
    :ok
  end

  describe "check_rate/2" do
    test "permet les requêtes dans la limite" do
      identifier = "test-user-#{System.unique_integer([:positive])}"

      # Première requête - doit passer
      assert {:allow, 4} = RateLimiter.check_rate(:magic_link_request, identifier)

      # Deuxième requête - doit passer
      assert {:allow, 3} = RateLimiter.check_rate(:magic_link_request, identifier)

      # Troisième requête - doit passer
      assert {:allow, 2} = RateLimiter.check_rate(:magic_link_request, identifier)
    end

    test "bloque les requêtes au-delà de la limite" do
      identifier = "spammer-#{System.unique_integer([:positive])}"

      # Utiliser toutes les 5 requêtes autorisées
      assert {:allow, 4} = RateLimiter.check_rate(:magic_link_request, identifier)
      assert {:allow, 3} = RateLimiter.check_rate(:magic_link_request, identifier)
      assert {:allow, 2} = RateLimiter.check_rate(:magic_link_request, identifier)
      assert {:allow, 1} = RateLimiter.check_rate(:magic_link_request, identifier)
      assert {:allow, 0} = RateLimiter.check_rate(:magic_link_request, identifier)

      # La 6ème requête doit être bloquée
      assert {:deny, retry_after} = RateLimiter.check_rate(:magic_link_request, identifier)
      assert is_integer(retry_after)
      assert retry_after > 0
    end

    test "isole les identifiants différents" do
      user1 = "user1-#{System.unique_integer([:positive])}"
      user2 = "user2-#{System.unique_integer([:positive])}"

      # User1 utilise toutes ses requêtes
      for _ <- 1..5 do
        assert {:allow, _} = RateLimiter.check_rate(:magic_link_request, user1)
      end

      assert {:deny, _} = RateLimiter.check_rate(:magic_link_request, user1)

      # User2 doit toujours pouvoir faire des requêtes
      assert {:allow, 4} = RateLimiter.check_rate(:magic_link_request, user2)
    end

    test "isole les actions différentes" do
      identifier = "test-#{System.unique_integer([:positive])}"

      # Utiliser toutes les requêtes magic_link
      for _ <- 1..5 do
        assert {:allow, _} = RateLimiter.check_rate(:magic_link_request, identifier)
      end

      assert {:deny, _} = RateLimiter.check_rate(:magic_link_request, identifier)

      # login_attempt doit toujours être disponible (limite de 10)
      assert {:allow, 9} = RateLimiter.check_rate(:login_attempt, identifier)
    end
  end

  describe "reset/2" do
    test "réinitialise le compteur pour un identifiant" do
      identifier = "test-reset-#{System.unique_integer([:positive])}"

      # Utiliser toutes les requêtes
      for _ <- 1..5 do
        assert {:allow, _} = RateLimiter.check_rate(:magic_link_request, identifier)
      end

      assert {:deny, _} = RateLimiter.check_rate(:magic_link_request, identifier)

      # Réinitialiser
      assert :ok = RateLimiter.reset(:magic_link_request, identifier)

      # Devrait pouvoir refaire des requêtes
      assert {:allow, 4} = RateLimiter.check_rate(:magic_link_request, identifier)
    end
  end

  describe "limit/1" do
    test "returns configured limit for magic_link_request" do
      {limit, period} = RateLimiter.limit(:magic_link_request)

      assert limit == 5
      assert period == :timer.hours(1)
    end

    test "returns configured limit for magic_link_verify" do
      {limit, period} = RateLimiter.limit(:magic_link_verify)

      assert limit == 10
      assert period == :timer.minutes(5)
    end

    test "returns configured limit for login_attempt" do
      {limit, period} = RateLimiter.limit(:login_attempt)

      assert limit == 10
      assert period == :timer.hours(1)
    end
  end

  describe "magic_link_verify rate limiting" do
    test "permet 10 vérifications par 5 minutes" do
      identifier = "verifier-#{System.unique_integer([:positive])}"

      # Utiliser les 10 tentatives autorisées
      for i <- 1..10 do
        assert {:allow, remaining} = RateLimiter.check_rate(:magic_link_verify, identifier)
        assert remaining == 10 - i
      end

      # La 11ème tentative doit être bloquée
      assert {:deny, retry_after} = RateLimiter.check_rate(:magic_link_verify, identifier)
      # Retry after devrait être ~5 minutes (300000 ms)
      assert retry_after <= :timer.minutes(5)
      assert retry_after > 0
    end

    test "période plus courte que magic_link_request" do
      {_, magic_link_period} = RateLimiter.limit(:magic_link_request)
      {_, verify_period} = RateLimiter.limit(:magic_link_verify)

      # Verify doit avoir une période plus courte (5 min vs 1 heure)
      assert verify_period < magic_link_period
    end
  end
end
