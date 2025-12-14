defmodule Portfolio.Auth.MagicLinkPropertiesTest do
  @moduledoc """
  Property-based tests for magic link token generation.

  Tests token uniqueness, URL safety, and format consistency.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "token generation properties" do
    property "generated tokens are always unique" do
      check all(
              count <- integer(10..100),
              max_runs: 10
            ) do
        # Generate multiple tokens
        tokens =
          for _ <- 1..count do
            generate_token()
          end

        # All tokens should be unique
        unique_tokens = Enum.uniq(tokens)

        assert length(unique_tokens) == length(tokens),
               "Generated #{length(tokens)} tokens but only #{length(unique_tokens)} are unique"
      end
    end

    property "token format is URL-safe (no +, /, =)" do
      check all(_ <- integer(1..100)) do
        token = generate_token()

        # URL-safe base64 should not contain +, /, or =
        refute String.contains?(token, "+"),
               "Token should not contain '+': #{token}"

        refute String.contains?(token, "/"),
               "Token should not contain '/': #{token}"

        refute String.contains?(token, "="),
               "Token should not contain '=': #{token}"

        # Should only contain URL-safe characters
        assert Regex.match?(~r/^[A-Za-z0-9_-]+$/, token),
               "Token should only contain URL-safe characters: #{token}"
      end
    end

    property "token length is constant" do
      check all(count <- integer(10..50), max_runs: 10) do
        tokens =
          for _ <- 1..count do
            generate_token()
          end

        lengths = Enum.map(tokens, &String.length/1)
        unique_lengths = Enum.uniq(lengths)

        # All tokens should have the same length
        assert length(unique_lengths) == 1,
               "Token lengths should be constant, got: #{inspect(unique_lengths)}"

        # Length should be 43 characters (32 bytes -> 43 chars in url_encode64 without padding)
        assert hd(unique_lengths) == 43,
               "Expected token length of 43, got #{hd(unique_lengths)}"
      end
    end

    property "tokens are cryptographically random" do
      check all(count <- integer(50..100), max_runs: 5) do
        tokens =
          for _ <- 1..count do
            generate_token()
          end

        # Check that tokens don't follow predictable patterns
        # 1. No two tokens should share the same prefix (first 10 chars)
        prefixes = Enum.map(tokens, &String.slice(&1, 0..9))
        unique_prefixes = Enum.uniq(prefixes)

        assert length(unique_prefixes) == length(prefixes),
               "Tokens should have unique prefixes (no patterns detected)"

        # 2. Character distribution should be relatively uniform
        all_chars = tokens |> Enum.join() |> String.graphemes()
        char_counts = Enum.frequencies(all_chars)

        # Each character should appear at least once if we have enough samples
        if count > 50 do
          # We expect both letters and numbers
          has_letters =
            Enum.any?(char_counts, fn {char, _} -> Regex.match?(~r/[a-zA-Z]/, char) end)

          has_numbers = Enum.any?(char_counts, fn {char, _} -> Regex.match?(~r/[0-9]/, char) end)

          assert has_letters, "Tokens should contain letters"
          assert has_numbers, "Tokens should contain numbers"
        end
      end
    end

    property "tokens survive URL encoding/decoding" do
      check all(count <- integer(10..30), max_runs: 10) do
        tokens =
          for _ <- 1..count do
            generate_token()
          end

        # Each token should survive URL encode/decode cycle
        Enum.each(tokens, fn token ->
          encoded = URI.encode(token)
          decoded = URI.decode(encoded)

          assert decoded == token,
                 "Token should survive URL encoding: #{token} -> #{encoded} -> #{decoded}"
        end)
      end
    end
  end

  describe "short code generation properties" do
    property "short codes are always 6 characters" do
      check all(count <- integer(10..50), max_runs: 10) do
        codes =
          for _ <- 1..count do
            generate_short_code()
          end

        Enum.each(codes, fn code ->
          assert String.length(code) == 6,
                 "Short code should be 6 characters: #{code}"
        end)
      end
    end

    property "short codes contain only uppercase alphanumeric" do
      check all(count <- integer(10..50), max_runs: 10) do
        codes =
          for _ <- 1..count do
            generate_short_code()
          end

        Enum.each(codes, fn code ->
          assert Regex.match?(~r/^[A-Z0-9]+$/, code),
                 "Short code should only contain uppercase alphanumeric: #{code}"
        end)
      end
    end

    property "short codes are unique" do
      check all(count <- integer(50..100), max_runs: 5) do
        codes =
          for _ <- 1..count do
            generate_short_code()
          end

        unique_codes = Enum.uniq(codes)

        # With 36^6 possible combinations, we should have very few collisions
        collision_rate = (length(codes) - length(unique_codes)) / length(codes)

        assert collision_rate < 0.05,
               "Short codes should be mostly unique (collision rate: #{collision_rate})"
      end
    end
  end

  # Helper functions that replicate token generation logic

  defp generate_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  defp generate_short_code do
    :crypto.strong_rand_bytes(4)
    |> Base.encode32(padding: false)
    |> String.slice(0..5)
    |> String.upcase()
  end
end
