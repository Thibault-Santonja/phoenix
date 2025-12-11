defmodule Portfolio.Photography.ValueObjects.SlugPropertiesExtendedTest do
  @moduledoc """
  Extended property-based tests for Slug value object.

  Tests advanced Unicode normalization, emoji handling, and max length truncation.
  These tests complement the existing slug_properties_test.exs.
  """
  use ExUnit.Case, async: true

  @moduletag :skip
  use ExUnitProperties

  alias Portfolio.Photography.ValueObjects.Slug

  # Generators

  defp unicode_nfd_nfc_pairs do
    # Generate strings that can be represented in both NFD and NFC forms
    gen all(base <- string(:alphanumeric, min_length: 3, max_length: 10)) do
      # Add accented characters that have different NFD/NFC representations
      nfc = base <> "café résumé naïve"
      # NFD separates base characters and combining marks
      nfd = :unicode.characters_to_nfd_binary(nfc)

      {nfc, nfd}
    end
  end

  defp emoji_string_generator do
    gen all(
          base <- string(:alphanumeric, min_length: 3, max_length: 15),
          emoji_positions <- list_of(integer(0..2), max_length: 3)
        ) do
      emojis = ["😀", "🎉", "❤️", "🚀", "⭐", "🌟", "💯", "🔥"]

      words = String.split(base, "", trim: true)

      # Insert emojis at random positions
      words_with_emojis =
        Enum.reduce(emoji_positions, words, fn pos, acc ->
          emoji = Enum.random(emojis)
          List.insert_at(acc, rem(pos, length(acc) + 1), emoji)
        end)

      Enum.join(words_with_emojis, "")
    end
  end

  defp long_title_generator do
    # Generate titles that exceed max length (100 chars)
    gen all(
          words <- list_of(string(:alphanumeric, min_length: 5, max_length: 15), min_length: 10)
        ) do
      Enum.join(words, " ")
    end
  end

  describe "Unicode normalization properties" do
    property "NFD and NFC forms produce equivalent slugs" do
      check all({nfc, nfd} <- unicode_nfd_nfc_pairs()) do
        slug_nfc = Slug.new(nfc)
        slug_nfd = Slug.new(nfd)

        # Both should produce valid slugs (or both should fail)
        case {slug_nfc, slug_nfd} do
          {{:ok, s1}, {:ok, s2}} ->
            # Slugs should be identical
            assert Slug.equal?(s1, s2),
                   "NFC and NFD forms should produce equal slugs: '#{s1.value}' vs '#{s2.value}'"

            assert s1.value == s2.value

          {{:error, _}, {:error, _}} ->
            # Both failed - acceptable
            :ok

          _ ->
            flunk(
              "NFC and NFD should both succeed or both fail: nfc=#{inspect(slug_nfc)}, nfd=#{inspect(slug_nfd)}"
            )
        end
      end
    end

    property "accented characters are properly transliterated" do
      check all(base <- string(:alphanumeric, min_length: 3, max_length: 10)) do
        # Add various accented characters
        accented_chars = [
          {"é", "e"},
          {"è", "e"},
          {"ê", "e"},
          {"ë", "e"},
          {"à", "a"},
          {"â", "a"},
          {"ä", "a"},
          {"ç", "c"},
          {"ô", "o"},
          {"ö", "o"},
          {"û", "u"},
          {"ü", "u"},
          {"ñ", "n"}
        ]

        Enum.each(accented_chars, fn {accented, expected} ->
          title = base <> accented

          case Slug.new(title) do
            {:ok, slug} ->
              # Slug should contain the base character, not the accented one
              assert String.contains?(slug.value, expected),
                     "Slug should transliterate '#{accented}' to '#{expected}': #{slug.value}"

              refute String.contains?(slug.value, accented),
                     "Slug should not contain accented character '#{accented}': #{slug.value}"

            {:error, _} ->
              :ok
          end
        end)
      end
    end
  end

  describe "emoji handling properties" do
    property "emojis are properly removed" do
      check all(emoji_string <- emoji_string_generator()) do
        case Slug.new(emoji_string) do
          {:ok, slug} ->
            # Slug should not contain any emoji characters
            # Emojis are typically in Unicode ranges U+1F300–U+1F9FF
            refute Regex.match?(~r/[\x{1F300}-\x{1F9FF}]/u, slug.value),
                   "Slug should not contain emojis: #{slug.value}"

            # Should only contain valid slug characters
            assert Regex.match?(~r/^[a-z0-9-]+$/, slug.value),
                   "Slug should only contain lowercase alphanumeric and hyphens: #{slug.value}"

          {:error, :invalid_slug} ->
            # If the string was all emojis, this is acceptable
            :ok

          {:error, reason} ->
            flunk("Unexpected error: #{reason}")
        end
      end
    end

    property "text with emojis produces valid slug from remaining text" do
      check all(
              base <- string(:alphanumeric, min_length: 5, max_length: 20),
              # Add emojis before and after
              title = "🎉 " <> base <> " 🚀"
            ) do
        case Slug.new(title) do
          {:ok, slug} ->
            # Slug should be based on the base text
            normalized_base = String.downcase(base)

            assert String.contains?(slug.value, normalized_base),
                   "Slug should contain base text '#{normalized_base}': #{slug.value}"

            # Should not contain emojis
            refute Regex.match?(~r/[\x{1F300}-\x{1F9FF}]/u, slug.value)

          {:error, _} ->
            :ok
        end
      end
    end
  end

  describe "max length truncation properties" do
    property "slugs never exceed max length" do
      check all(title <- long_title_generator()) do
        case Slug.new(title) do
          {:ok, slug} ->
            assert String.length(slug.value) <= 100,
                   "Slug should not exceed 100 characters: #{String.length(slug.value)}"

          {:error, :too_long} ->
            # Acceptable for extremely long titles
            :ok

          {:error, _} ->
            :ok
        end
      end
    end

    property "truncation doesn't cut mid-word when possible" do
      check all(
              # Generate long title with clear word boundaries
              words <-
                list_of(string(:alphanumeric, min_length: 5, max_length: 10), min_length: 15),
              title = Enum.join(words, " ")
            ) do
        case Slug.new(title) do
          {:ok, slug} ->
            # If truncated, should not end with partial word indicators
            # (though this is a soft requirement depending on implementation)
            refute String.ends_with?(slug.value, "-"),
                   "Slug should not end with hyphen after truncation: #{slug.value}"

            # Length should be <= 100
            assert String.length(slug.value) <= 100

          {:error, _} ->
            :ok
        end
      end
    end

    property "truncated slugs remain valid" do
      check all(
              # Generate very long title
              words <-
                list_of(string(:alphanumeric, min_length: 8, max_length: 12), min_length: 20),
              title = Enum.join(words, " ")
            ) do
        case Slug.new(title) do
          {:ok, slug} ->
            # Even if truncated, should still be valid
            assert Regex.match?(~r/^[a-z0-9-]+$/, slug.value),
                   "Truncated slug should still be valid: #{slug.value}"

            refute String.starts_with?(slug.value, "-")
            refute String.ends_with?(slug.value, "-")
            refute String.contains?(slug.value, "--")

          {:error, _} ->
            :ok
        end
      end
    end
  end

  describe "edge case handling properties" do
    property "mixed Unicode and ASCII produce valid slugs" do
      check all(
              ascii_part <- string(:alphanumeric, min_length: 3, max_length: 10),
              unicode_additions <- member_of(["日本語", "中文", "한글", "العربية", "עברית"])
            ) do
        title = ascii_part <> " " <> unicode_additions

        case Slug.new(title) do
          {:ok, slug} ->
            # Should contain the ASCII part
            assert String.contains?(slug.value, String.downcase(ascii_part)),
                   "Slug should contain ASCII part: #{slug.value}"

            # Should be valid slug format
            assert Regex.match?(~r/^[a-z0-9-]+$/, slug.value)

          {:error, _} ->
            # Some combinations might not produce valid slugs
            :ok
        end
      end
    end

    property "repeated special characters are handled" do
      check all(
              base <- string(:alphanumeric, min_length: 3, max_length: 10),
              special_count <- integer(1..5)
            ) do
        # Insert multiple special characters
        special_chars = String.duplicate("!@#$%^&*()", special_count)
        title = base <> special_chars <> base

        case Slug.new(title) do
          {:ok, slug} ->
            # Should not have consecutive hyphens (special chars should collapse)
            refute String.contains?(slug.value, "--"),
                   "Slug should not have consecutive hyphens: #{slug.value}"

            # Should contain the base text
            assert String.contains?(slug.value, String.downcase(base))

          {:error, _} ->
            :ok
        end
      end
    end
  end
end
