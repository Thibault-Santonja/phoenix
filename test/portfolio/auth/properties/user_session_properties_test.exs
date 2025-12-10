defmodule Portfolio.Auth.Properties.UserSessionPropertiesTest do
  @moduledoc """
  Property-based tests for UserSession token hashing.

  Tests cryptographic properties of the token hashing function.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Portfolio.Auth.UserSession

  describe "hash_token_value properties" do
    property "hash is deterministic (same input = same output)" do
      check all(token <- string(:printable, min_length: 1, max_length: 100)) do
        hash1 = UserSession.hash_token_value(token)
        hash2 = UserSession.hash_token_value(token)
        assert hash1 == hash2
      end
    end

    property "hash is always 64 characters (SHA-256 hex)" do
      check all(token <- string(:printable, min_length: 1, max_length: 100)) do
        hash = UserSession.hash_token_value(token)
        assert String.length(hash) == 64
      end
    end

    property "hash contains only lowercase hex characters" do
      check all(token <- string(:printable, min_length: 1, max_length: 100)) do
        hash = UserSession.hash_token_value(token)
        assert Regex.match?(~r/^[0-9a-f]+$/, hash)
      end
    end

    property "different inputs produce different hashes (collision resistance)" do
      check all(
              token1 <- string(:printable, min_length: 1, max_length: 50),
              token2 <- string(:printable, min_length: 1, max_length: 50),
              token1 != token2
            ) do
        hash1 = UserSession.hash_token_value(token1)
        hash2 = UserSession.hash_token_value(token2)
        assert hash1 != hash2, "Different tokens should produce different hashes"
      end
    end

    property "hash changes completely with small input change (avalanche effect)" do
      check all(token <- string(:alphanumeric, min_length: 5, max_length: 50)) do
        original_hash = UserSession.hash_token_value(token)
        modified_token = token <> "x"
        modified_hash = UserSession.hash_token_value(modified_token)

        # Hashes should be completely different
        assert original_hash != modified_hash

        # Count differing characters (should be significant)
        diff_count =
          Enum.zip(String.graphemes(original_hash), String.graphemes(modified_hash))
          |> Enum.count(fn {a, b} -> a != b end)

        # At least half the characters should differ (avalanche property)
        assert diff_count >= 16,
               "Avalanche effect: expected >= 16 different chars, got #{diff_count}"
      end
    end

    property "empty string produces valid hash" do
      hash = UserSession.hash_token_value("")
      assert String.length(hash) == 64
      assert Regex.match?(~r/^[0-9a-f]+$/, hash)
    end

    property "unicode tokens are hashed correctly" do
      check all(token <- string(:printable, min_length: 1, max_length: 50)) do
        unicode_token = token <> "éàü日本語"
        hash = UserSession.hash_token_value(unicode_token)
        assert String.length(hash) == 64
        assert Regex.match?(~r/^[0-9a-f]+$/, hash)
      end
    end
  end
end
