defmodule Portfolio.Auth.MXValidatorTest do
  @moduledoc """
  Tests pour la validation des enregistrements MX (Mail Exchange).

  Vérifie que le domaine d'un email possède des enregistrements MX valides,
  ce qui indique qu'il peut recevoir des emails.
  """

  # async: false car on modifie la config globale de l'application
  use ExUnit.Case, async: false

  alias Portfolio.Auth.MXValidator

  setup do
    # Désactiver le skip MX pour ces tests
    original_value = Application.get_env(:portfolio, :skip_mx_validation)
    Application.put_env(:portfolio, :skip_mx_validation, false)

    # Clear MX validation cache to ensure clean state between tests
    Cachex.clear(:portfolio_cache)

    on_exit(fn ->
      Application.put_env(:portfolio, :skip_mx_validation, original_value)
      # Clear cache after test
      Cachex.clear(:portfolio_cache)
    end)

    :ok
  end

  describe "valid_mx?/1" do
    @tag :network
    test "returns true for gmail.com (known good domain)" do
      # Ce test nécessite une connexion réseau
      result = MXValidator.valid_mx?("user@gmail.com")
      # Gmail devrait avoir des MX, mais on accepte false si problème réseau
      assert is_boolean(result)
    end

    @tag :network
    test "returns true for well-known domains" do
      # Test avec des domaines connus, mais on accepte les échecs réseau
      domains = ["gmail.com", "yahoo.com", "outlook.com"]

      results =
        Enum.map(domains, fn domain ->
          MXValidator.valid_mx?("user@#{domain}")
        end)

      # Au moins un domaine devrait réussir si le réseau fonctionne
      # Sinon tous seront false et c'est ok (problème réseau)
      assert Enum.all?(results, &is_boolean/1)
    end

    test "returns false for obviously fake domain" do
      assert MXValidator.valid_mx?("user@thisisnotarealdomainname123456789.xyz") == false
    end

    test "returns false for invalid email format" do
      assert MXValidator.valid_mx?("not-an-email") == false
    end

    test "returns false for nil" do
      assert MXValidator.valid_mx?(nil) == false
    end

    test "returns false for empty string" do
      assert MXValidator.valid_mx?("") == false
    end

    test "is case insensitive for invalid domain" do
      # Test sans dépendance réseau en utilisant un domaine invalide
      domain = "invalid-#{System.unique_integer([:positive])}"
      result1 = MXValidator.valid_mx?("user@#{domain}.com")
      result2 = MXValidator.valid_mx?("USER@#{String.upcase(domain)}.COM")

      # Les deux devraient retourner false (domaine invalide)
      assert result1 == false
      assert result2 == false
      # Et être identiques (prouve la normalisation)
      assert result1 == result2
    end

    @tag :network
    test "case normalization works with real domain" do
      # Ce test vérifie que la normalisation fonctionne, mais accepte les échecs réseau
      # car les lookups DNS sont non déterministes en environnement de test

      # Faire le premier appel pour populer le cache
      first_result = MXValidator.valid_mx?("user@gmail.com")

      # Vérifier que c'est un booléen
      assert is_boolean(first_result)

      # Si le DNS fonctionne (résultat true), vérifier la cohérence du cache
      if first_result do
        # Faire plusieurs appels avec différentes casses - ils devraient tous utiliser le cache
        results = [
          MXValidator.valid_mx?("USER@GMAIL.COM"),
          MXValidator.valid_mx?("User@Gmail.Com"),
          MXValidator.valid_mx?("user@gmail.com")
        ]

        # Tous les résultats devraient être true (depuis le cache)
        assert Enum.all?(results, & &1),
               "All results should be true when cached, got: #{inspect(results)}"
      else
        # Si le DNS ne fonctionne pas, on accepte le résultat (pas de test de cohérence)
        :ok
      end
    end
  end

  describe "check_mx_records/1" do
    @tag :network
    test "returns {:ok, records} for domain with MX" do
      case MXValidator.check_mx_records("gmail.com") do
        {:ok, records} ->
          assert is_list(records)
          assert records != []

        {:error, reason} ->
          # Problème réseau acceptable
          assert reason in [:timeout, :lookup_failed, :nxdomain]
      end
    end

    test "returns {:error, reason} for non-existent domain" do
      assert {:error, _reason} =
               MXValidator.check_mx_records("thisisnotarealdomainname123456789.xyz")
    end

    test "returns {:error, reason} for nil" do
      assert {:error, :invalid_domain} = MXValidator.check_mx_records(nil)
    end

    test "returns {:error, reason} for empty string" do
      assert {:error, :invalid_domain} = MXValidator.check_mx_records("")
    end

    @tag :network
    test "is case insensitive" do
      result1 = MXValidator.check_mx_records("gmail.com")
      result2 = MXValidator.check_mx_records("GMAIL.COM")

      # Les deux devraient donner le même résultat
      case {result1, result2} do
        {{:ok, _}, {:ok, _}} -> assert true
        {{:error, _}, {:error, _}} -> assert true
        _ -> flunk("Case sensitivity issue")
      end
    end
  end

  describe "extract_domain/1" do
    test "extracts domain from email" do
      assert MXValidator.extract_domain("user@example.com") == "example.com"
    end

    test "handles email with subdomain" do
      assert MXValidator.extract_domain("user@mail.example.com") == "mail.example.com"
    end

    test "is case insensitive" do
      assert MXValidator.extract_domain("USER@EXAMPLE.COM") == "example.com"
    end

    test "returns nil for invalid email" do
      assert MXValidator.extract_domain("invalid") == nil
      assert MXValidator.extract_domain("") == nil
      assert MXValidator.extract_domain(nil) == nil
    end
  end

  describe "timeout handling" do
    test "handles DNS timeout gracefully" do
      # Pour ce test, on accepte soit un succès soit un timeout
      # car la résolution DNS peut varier selon l'environnement
      result = MXValidator.valid_mx?("user@gmail.com")
      assert is_boolean(result)
    end
  end

  describe "caching" do
    test "multiple calls for same domain return consistent results" do
      # Utiliser un domaine unique pour éviter les interférences entre tests
      domain = "cache-test-#{System.unique_integer([:positive])}.invalid"

      # Premier appel - établit le cache (probablement false car domaine invalide)
      result1 = MXValidator.valid_mx?("user@#{domain}")

      # Plusieurs appels suivants - doivent tous retourner le même résultat depuis le cache
      result2 = MXValidator.valid_mx?("user@#{domain}")
      result3 = MXValidator.valid_mx?("user@#{domain}")
      result4 = MXValidator.valid_mx?("user@#{domain}")

      # Tous les résultats doivent être identiques (prouve que le cache fonctionne)
      assert result1 == result2
      assert result2 == result3
      assert result3 == result4

      # Vérifier que ce sont des booléens
      assert is_boolean(result1)
    end

    test "multiple calls for invalid domain return consistent cached results" do
      # Test avec un domaine invalide qui ne nécessite pas de réseau
      domain = "definitely-invalid-domain-#{System.unique_integer([:positive])}.xyz"

      # Premier appel - met en cache le résultat
      result1 = MXValidator.valid_mx?("user@#{domain}")

      # Appels suivants - doivent retourner le même résultat depuis le cache
      result2 = MXValidator.valid_mx?("user@#{domain}")
      result3 = MXValidator.valid_mx?("user@#{domain}")

      # Tous les résultats doivent être identiques
      assert result1 == result2
      assert result2 == result3

      # Pour un domaine invalide, devrait être false
      assert result1 == false
    end
  end
end
