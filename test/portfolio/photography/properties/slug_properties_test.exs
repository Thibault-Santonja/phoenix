defmodule Portfolio.Photography.Properties.SlugPropertiesTest do
  @moduledoc """
  Property-based tests for the Slug value object.

  Tests invariants that must hold for all valid slug inputs.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Portfolio.Photography.ValueObjects.Slug

  # Generators
  defp non_empty_title_generator do
    gen all(
          words <-
            list_of(string(:alphanumeric, min_length: 1, max_length: 10),
              min_length: 1,
              max_length: 5
            )
        ) do
      Enum.join(words, " ")
    end
  end

  defp unicode_title_generator do
    gen all(base <- non_empty_title_generator()) do
      # Add some unicode characters
      base <> " café résumé naïve"
    end
  end

  describe "slug creation properties" do
    property "slugs are always URL-safe" do
      check all(title <- non_empty_title_generator()) do
        case Slug.new(title) do
          {:ok, slug} ->
            # URL-safe: only lowercase alphanumeric and hyphens
            assert Regex.match?(~r/^[a-z0-9-]+$/, slug.value)

          {:error, _} ->
            # Empty results are acceptable for some inputs
            :ok
        end
      end
    end

    property "slugs never start or end with hyphen" do
      check all(title <- non_empty_title_generator()) do
        case Slug.new(title) do
          {:ok, slug} ->
            refute String.starts_with?(slug.value, "-"),
                   "Slug should not start with hyphen: #{slug.value}"

            refute String.ends_with?(slug.value, "-"),
                   "Slug should not end with hyphen: #{slug.value}"

          {:error, _} ->
            :ok
        end
      end
    end

    property "slugs never have consecutive hyphens" do
      check all(title <- non_empty_title_generator()) do
        case Slug.new(title) do
          {:ok, slug} ->
            refute String.contains?(slug.value, "--"),
                   "Slug should not have consecutive hyphens: #{slug.value}"

          {:error, _} ->
            :ok
        end
      end
    end

    property "slug length is bounded" do
      check all(title <- non_empty_title_generator()) do
        case Slug.new(title) do
          {:ok, slug} ->
            assert String.length(slug.value) <= 100
            assert String.length(slug.value) >= 1

          {:error, :too_long} ->
            # Long titles may exceed the limit
            :ok

          {:error, :invalid_slug} ->
            # Some titles may produce empty slugs
            :ok
        end
      end
    end

    property "slug creation is deterministic" do
      check all(title <- non_empty_title_generator()) do
        result1 = Slug.new(title)
        result2 = Slug.new(title)
        assert result1 == result2
      end
    end

    property "valid slugs can be recreated from their value" do
      check all(title <- non_empty_title_generator()) do
        case Slug.new(title) do
          {:ok, slug} ->
            # Creating a slug from an already valid slug value should be idempotent
            {:ok, slug2} = Slug.new(slug.value)
            assert slug.value == slug2.value

          {:error, _} ->
            :ok
        end
      end
    end
  end

  describe "slug equality properties" do
    property "slug equality is based on value" do
      check all(title <- non_empty_title_generator()) do
        case Slug.new(title) do
          {:ok, slug1} ->
            {:ok, slug2} = Slug.new(title)
            assert Slug.equal?(slug1, slug2)

          {:error, _} ->
            :ok
        end
      end
    end

    property "equal? is symmetric" do
      check all(title <- non_empty_title_generator()) do
        case Slug.new(title) do
          {:ok, slug1} ->
            {:ok, slug2} = Slug.new(title)
            assert Slug.equal?(slug1, slug2) == Slug.equal?(slug2, slug1)

          {:error, _} ->
            :ok
        end
      end
    end
  end

  describe "unicode handling properties" do
    property "unicode titles produce ASCII slugs" do
      check all(title <- unicode_title_generator()) do
        case Slug.new(title) do
          {:ok, slug} ->
            # All characters should be ASCII
            assert String.to_charlist(slug.value) |> Enum.all?(&(&1 < 128)),
                   "Slug should be ASCII only: #{slug.value}"

          {:error, _} ->
            :ok
        end
      end
    end
  end

  describe "edge cases" do
    test "empty string returns error" do
      assert {:error, :invalid_slug} = Slug.new("")
    end

    test "whitespace only returns error" do
      assert {:error, :invalid_slug} = Slug.new("   ")
    end

    test "special characters only returns error" do
      assert {:error, :invalid_slug} = Slug.new("!@#$%^&*()")
    end
  end
end
