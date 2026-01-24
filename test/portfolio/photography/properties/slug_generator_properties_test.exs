defmodule Portfolio.Photography.Properties.SlugGeneratorPropertiesTest do
  @moduledoc """
  Property-based tests for SlugGenerator collision resistance.

  Tests that the slug generation strategy correctly handles collisions
  and produces unique slugs across various input combinations.
  """
  use Portfolio.DataCase, async: true
  use ExUnitProperties

  alias Portfolio.Photography.Repositories.AlbumRepository
  alias Portfolio.Photography.Services.SlugGenerator

  import PortfolioTest.Fixtures.PhotographyFixtures

  # Generators
  defp valid_title_generator do
    gen all(
          words <-
            list_of(string(:alphanumeric, min_length: 2, max_length: 8),
              min_length: 1,
              max_length: 3
            )
        ) do
      Enum.join(words, " ")
    end
  end

  defp date_generator do
    # Use past dates only to avoid validation errors
    gen all(
          year <- integer(2020..2024),
          month <- integer(1..12),
          day <- integer(1..28)
        ) do
      Date.new!(year, month, day)
    end
  end

  describe "collision resistance properties" do
    property "same title with different years produces unique slugs" do
      check all(
              title <- valid_title_generator(),
              year1 <- integer(2020..2022),
              year2 <- integer(2023..2024)
            ) do
        date1 = Date.new!(year1, 6, 15)
        date2 = Date.new!(year2, 6, 15)

        {:ok, slug1} = SlugGenerator.generate_unique_slug(title, date1)
        # Create album with first slug
        _album = create_album_with_slug(slug1, date1)

        # Second generation should produce different slug
        {:ok, slug2} = SlugGenerator.generate_unique_slug(title, date2)

        assert slug1 != slug2, "Slugs should be different: #{slug1} vs #{slug2}"
      end
    end

    property "collision resolution adds date suffix progressively" do
      check all(
              title <- valid_title_generator(),
              date <- date_generator()
            ) do
        {:ok, base_slug} = SlugGenerator.generate_unique_slug(title, date)

        # Create album with base slug
        _album1 = create_album_with_slug(base_slug, date)

        # Next generation should add year suffix
        {:ok, slug_with_year} = SlugGenerator.generate_unique_slug(title, date)

        assert slug_with_year =~ ~r/-\d{4}$/,
               "Slug should end with year: #{slug_with_year}"

        # Create album with year suffix
        _album2 = create_album_with_slug(slug_with_year, date)

        # Next generation should add month suffix
        {:ok, slug_with_month} = SlugGenerator.generate_unique_slug(title, date)

        assert slug_with_month =~ ~r/-\d{4}-\d{2}$/,
               "Slug should end with year-month: #{slug_with_month}"
      end
    end

    property "generated slugs are always valid" do
      check all(
              title <- valid_title_generator(),
              date <- date_generator()
            ) do
        case SlugGenerator.generate_unique_slug(title, date) do
          {:ok, slug} ->
            # Must be URL-safe
            assert Regex.match?(~r/^[a-z0-9-]+$/, slug),
                   "Slug must be URL-safe: #{slug}"

            # Must not have consecutive hyphens
            refute String.contains?(slug, "--"),
                   "Slug must not have consecutive hyphens: #{slug}"

            # Must not start or end with hyphen
            refute String.starts_with?(slug, "-"),
                   "Slug must not start with hyphen: #{slug}"

            refute String.ends_with?(slug, "-"),
                   "Slug must not end with hyphen: #{slug}"

          {:error, reason} ->
            # Some inputs may be invalid
            assert reason in [:invalid_slug, :too_long, :unable_to_generate_unique_slug]
        end
      end
    end

    property "slug generation is deterministic for same DB state" do
      check all(
              title <- valid_title_generator(),
              date <- date_generator()
            ) do
        # Same title and date should produce same slug when DB state is same
        result1 = SlugGenerator.generate_unique_slug(title, date)
        result2 = SlugGenerator.generate_unique_slug(title, date)

        assert result1 == result2
      end
    end
  end

  describe "uniqueness guarantees" do
    property "generated slug is never already in database" do
      check all(
              title <- valid_title_generator(),
              date <- date_generator()
            ) do
        {:ok, slug} = SlugGenerator.generate_unique_slug(title, date)

        # Verify slug doesn't exist in database
        assert {:error, :not_found} = AlbumRepository.get_by_slug(slug)
      end
    end

    property "multiple generations with same title produce different slugs" do
      check all(
              title <- valid_title_generator(),
              date <- date_generator(),
              max_runs: 20
            ) do
        slugs =
          Enum.reduce_while(1..4, [], fn _, acc ->
            case SlugGenerator.generate_unique_slug(title, date) do
              {:ok, slug} ->
                _album = create_album_with_slug(slug, date)
                {:cont, [slug | acc]}

              {:error, :unable_to_generate_unique_slug} ->
                # Expected after 4 iterations with same date
                {:halt, acc}
            end
          end)

        # All generated slugs must be unique
        assert slugs == Enum.uniq(slugs),
               "All slugs must be unique: #{inspect(slugs)}"
      end
    end
  end

  describe "date suffix format" do
    property "year suffix is 4 digits" do
      check all(
              title <- valid_title_generator(),
              date <- date_generator()
            ) do
        {:ok, base_slug} = SlugGenerator.generate_unique_slug(title, date)
        _album = create_album_with_slug(base_slug, date)

        {:ok, slug_with_year} = SlugGenerator.generate_unique_slug(title, date)

        if slug_with_year != base_slug do
          # Extract year suffix
          year_suffix = String.slice(slug_with_year, -4, 4)
          assert Regex.match?(~r/^\d{4}$/, year_suffix)
        end
      end
    end

    property "month suffix is zero-padded" do
      check all(
              title <- valid_title_generator(),
              year <- integer(2020..2024),
              month <- integer(1..9)
            ) do
        date = Date.new!(year, month, 15)

        # Create base and year slugs
        {:ok, slug1} = SlugGenerator.generate_unique_slug(title, date)
        _album1 = create_album_with_slug(slug1, date)

        {:ok, slug2} = SlugGenerator.generate_unique_slug(title, date)
        _album2 = create_album_with_slug(slug2, date)

        {:ok, slug3} = SlugGenerator.generate_unique_slug(title, date)

        # Month should be zero-padded
        if String.contains?(slug3, "-0#{month}") or String.contains?(slug3, "-#{month}") do
          assert slug3 =~ ~r/-\d{4}-0#{month}/,
                 "Month #{month} should be zero-padded in: #{slug3}"
        end
      end
    end
  end

  # Helper to create album with specific slug
  defp create_album_with_slug(slug, date) do
    create_album(
      title: "Test Album #{slug}",
      slug: slug,
      type: :wedding,
      date_prise_vue: date
    )
  end
end
