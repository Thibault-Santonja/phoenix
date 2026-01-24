defmodule Portfolio.Auth.Properties.EmailNormalizerPropertiesTest do
  @moduledoc """
  Property-based tests for email normalization.

  Tests invariants that must hold for all email inputs.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Portfolio.Auth.EmailNormalizer

  # Generators
  defp simple_local_generator do
    string(:alphanumeric, min_length: 1, max_length: 20)
  end

  defp domain_generator do
    gen all(
          domain_part <- string(:alphanumeric, min_length: 1, max_length: 10),
          tld <- member_of(["com", "org", "net", "io", "dev"])
        ) do
      "#{domain_part}.#{tld}"
    end
  end

  defp valid_email_generator do
    gen all(
          local <- simple_local_generator(),
          domain <- domain_generator()
        ) do
      "#{local}@#{domain}"
    end
  end

  defp gmail_local_with_dots_generator do
    gen all(
          parts <-
            list_of(string(:alphanumeric, min_length: 1, max_length: 5),
              min_length: 2,
              max_length: 4
            )
        ) do
      Enum.join(parts, ".")
    end
  end

  describe "normalization properties" do
    property "normalization is idempotent" do
      check all(email <- valid_email_generator()) do
        once = EmailNormalizer.normalize(email)
        twice = EmailNormalizer.normalize(once)
        assert once == twice
      end
    end

    property "normalized emails are always lowercase" do
      check all(email <- valid_email_generator()) do
        normalized = EmailNormalizer.normalize(email)
        assert normalized == String.downcase(normalized)
      end
    end

    property "normalized emails have no leading/trailing whitespace" do
      # Generate whitespace strings using space and tab characters
      whitespace_gen = string([?\s, ?\t, ?\n, ?\r], max_length: 3)

      check all(
              email <- valid_email_generator(),
              leading <- whitespace_gen,
              trailing <- whitespace_gen
            ) do
        padded = leading <> email <> trailing
        normalized = EmailNormalizer.normalize(padded)
        assert normalized == String.trim(normalized)
      end
    end

    property "normalization preserves @ separator" do
      check all(email <- valid_email_generator()) do
        normalized = EmailNormalizer.normalize(email)
        assert String.contains?(normalized, "@")
        parts = String.split(normalized, "@")
        assert length(parts) == 2
      end
    end

    property "nil returns nil" do
      assert EmailNormalizer.normalize(nil) == nil
    end

    property "empty string returns empty string" do
      assert EmailNormalizer.normalize("") == ""
    end
  end

  describe "Gmail normalization properties" do
    property "Gmail addresses have dots removed from local part" do
      check all(local <- gmail_local_with_dots_generator()) do
        email = "#{local}@gmail.com"
        normalized = EmailNormalizer.normalize(email)

        [normalized_local, _domain] = String.split(normalized, "@")
        # Dots should be removed from local part (before any +)
        base_local = String.split(normalized_local, "+") |> hd()
        refute String.contains?(base_local, ".")
      end
    end

    property "Gmail plus addressing is preserved" do
      check all(
              local <- simple_local_generator(),
              tag <- string(:alphanumeric, min_length: 1, max_length: 10)
            ) do
        email = "#{local}+#{tag}@gmail.com"
        normalized = EmailNormalizer.normalize(email)

        assert String.contains?(normalized, "+#{String.downcase(tag)}@")
      end
    end

    property "googlemail.com is treated like gmail.com" do
      check all(local <- gmail_local_with_dots_generator()) do
        gmail = EmailNormalizer.normalize("#{local}@gmail.com")
        googlemail = EmailNormalizer.normalize("#{local}@googlemail.com")

        # Both should have dots removed
        [gmail_local, _] = String.split(gmail, "@")
        [googlemail_local, _] = String.split(googlemail, "@")
        assert gmail_local == googlemail_local
      end
    end
  end

  describe "non-Gmail domain properties" do
    property "non-Gmail domains preserve dots in local part" do
      check all(
              local <- gmail_local_with_dots_generator(),
              domain <- member_of(["yahoo.com", "outlook.com", "example.com"])
            ) do
        email = "#{local}@#{domain}"
        normalized = EmailNormalizer.normalize(email)

        [normalized_local, _] = String.split(normalized, "@")
        # Dots should be preserved for non-Gmail
        if String.contains?(local, ".") do
          assert String.contains?(normalized_local, ".")
        end
      end
    end
  end

  describe "gmail_domain? properties" do
    property "gmail_domain? is case insensitive" do
      check all(case_variant <- member_of(["gmail.com", "Gmail.Com", "GMAIL.COM", "gMaIl.CoM"])) do
        assert EmailNormalizer.gmail_domain?(case_variant)
      end
    end

    property "non-Gmail domains return false" do
      check all(
              domain_part <- string(:alphanumeric, min_length: 3, max_length: 10),
              tld <- member_of(["com", "org", "net"])
            ) do
        domain = "#{domain_part}.#{tld}"

        unless domain in ["gmail.com", "googlemail.com"] do
          refute EmailNormalizer.gmail_domain?(domain)
        end
      end
    end
  end
end
