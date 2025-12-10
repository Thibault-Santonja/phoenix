defmodule Portfolio.Auth.Properties.DisposableEmailPropertiesTest do
  @moduledoc """
  Property-based tests for disposable email detection.

  Tests invariants that must hold for email domain checking.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Portfolio.Auth.DisposableEmailChecker

  # Generators
  defp local_part_generator do
    string(:alphanumeric, min_length: 1, max_length: 20)
  end

  defp safe_domain_generator do
    gen all(
          domain_part <- string(:alphanumeric, min_length: 3, max_length: 10),
          tld <- member_of(["com", "org", "net", "io", "dev", "fr"])
        ) do
      "#{domain_part}.#{tld}"
    end
  end

  defp disposable_domain_generator do
    member_of(DisposableEmailChecker.disposable_domains())
  end

  describe "disposable? properties" do
    property "nil always returns false" do
      refute DisposableEmailChecker.disposable?(nil)
    end

    property "empty string always returns false" do
      refute DisposableEmailChecker.disposable?("")
    end

    property "invalid emails (no @) return false" do
      check all(str <- string(:alphanumeric, min_length: 1, max_length: 30)) do
        refute DisposableEmailChecker.disposable?(str)
      end
    end

    property "known disposable domains are detected" do
      check all(
              local <- local_part_generator(),
              domain <- disposable_domain_generator()
            ) do
        email = "#{local}@#{domain}"

        assert DisposableEmailChecker.disposable?(email),
               "Should detect #{email} as disposable"
      end
    end

    property "subdomains of disposable domains are detected" do
      check all(
              local <- local_part_generator(),
              subdomain <- string(:alphanumeric, min_length: 2, max_length: 8),
              domain <- disposable_domain_generator()
            ) do
        email = "#{local}@#{subdomain}.#{domain}"

        assert DisposableEmailChecker.disposable?(email),
               "Should detect subdomain #{email} as disposable"
      end
    end

    property "detection is case insensitive" do
      check all(
              local <- local_part_generator(),
              domain <- disposable_domain_generator()
            ) do
        lower = "#{local}@#{domain}"
        upper = "#{String.upcase(local)}@#{String.upcase(domain)}"
        mixed = "#{local}@#{String.capitalize(domain)}"

        assert DisposableEmailChecker.disposable?(lower)
        assert DisposableEmailChecker.disposable?(upper)
        assert DisposableEmailChecker.disposable?(mixed)
      end
    end
  end

  describe "extract_domain properties" do
    property "extracts domain correctly from valid emails" do
      check all(
              local <- local_part_generator(),
              domain <- safe_domain_generator()
            ) do
        email = "#{local}@#{domain}"
        extracted = DisposableEmailChecker.extract_domain(email)
        assert extracted == String.downcase(domain)
      end
    end

    property "extracted domain is always lowercase" do
      check all(
              local <- local_part_generator(),
              domain <- safe_domain_generator()
            ) do
        email = "#{String.upcase(local)}@#{String.upcase(domain)}"
        extracted = DisposableEmailChecker.extract_domain(email)

        if extracted do
          assert extracted == String.downcase(extracted)
        end
      end
    end

    property "nil input returns nil" do
      assert DisposableEmailChecker.extract_domain(nil) == nil
    end

    property "empty string returns nil" do
      assert DisposableEmailChecker.extract_domain("") == nil
    end

    property "strings without @ return nil" do
      check all(str <- string(:alphanumeric, min_length: 1, max_length: 30)) do
        assert DisposableEmailChecker.extract_domain(str) == nil
      end
    end
  end

  describe "disposable_domains properties" do
    property "all domains in list are lowercase" do
      domains = DisposableEmailChecker.disposable_domains()

      Enum.each(domains, fn domain ->
        assert domain == String.downcase(domain),
               "Domain #{domain} should be lowercase"
      end)
    end

    property "all domains in list are valid domain format" do
      domains = DisposableEmailChecker.disposable_domains()

      Enum.each(domains, fn domain ->
        assert String.contains?(domain, "."),
               "Domain #{domain} should contain a dot"

        refute String.starts_with?(domain, "."),
               "Domain #{domain} should not start with a dot"

        refute String.ends_with?(domain, "."),
               "Domain #{domain} should not end with a dot"
      end)
    end

    property "list is not empty" do
      domains = DisposableEmailChecker.disposable_domains()
      assert length(domains) > 0
    end

    property "common disposable domains are included" do
      domains = DisposableEmailChecker.disposable_domains()
      common = ["mailinator.com", "guerrillamail.com", "10minutemail.com"]

      Enum.each(common, fn domain ->
        assert domain in domains, "Common domain #{domain} should be in the list"
      end)
    end
  end
end
