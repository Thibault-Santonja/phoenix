defmodule PortfolioWeb.SEO.SchemaHelpers do
  @moduledoc """
  Helpers for generating Schema.org JSON-LD structured data.

  Provides functions to generate rich snippets for Google Search:
  - ImageGallery and ImageObject for photography pages
  - Person schema for photographer profile
  - BreadcrumbList for navigation
  - WebSite for site-wide search

  All schemas follow Schema.org vocabulary and Google's structured data guidelines:
  https://schema.org/
  https://developers.google.com/search/docs/appearance/structured-data
  """

  @doc """
  Generates JSON-LD structured data for an image gallery (album page).

  ## Parameters
  - `album` - Album struct
  - `photos` - List of Photo structs
  - `url` - Full URL of the page

  ## Example
      iex> image_gallery_schema(album, photos, "https://photo.thibaultsan.com/album-slug")
      "{\"@context\":\"https://schema.org\",...}"
  """
  def image_gallery_schema(album, photos, url) do
    schema = %{
      "@context" => "https://schema.org",
      "@type" => "ImageGallery",
      "name" => album.title,
      "description" => album.description || album.title,
      "url" => url,
      "datePublished" => format_date(album.inserted_at),
      "dateModified" => format_date(album.updated_at || album.inserted_at),
      "author" => photographer_schema(),
      "image" => Enum.map(photos, &image_object_schema(&1, album))
    }

    Jason.encode!(schema)
  end

  @doc """
  Generates Schema.org ImageObject for a single photo.

  ## Parameters
  - `photo` - Photo struct
  - `album` - Album struct (for context)
  """
  def image_object_schema(photo, album) do
    %{
      "@type" => "ImageObject",
      "contentUrl" => build_image_url(photo.file_path),
      "name" => photo.title || "#{album.title} - Photo",
      "caption" => photo.description || album.description,
      "datePublished" => format_date(photo.inserted_at),
      "author" => photographer_schema(),
      "copyrightHolder" => photographer_schema(),
      "copyrightYear" => extract_year(photo.inserted_at)
    }
    |> maybe_add_exif_data(photo.exif_data)
  end

  @doc """
  Generates Schema.org Person schema for the photographer.
  """
  def photographer_schema do
    %{
      "@type" => "Person",
      "name" => "Thibault Santonja",
      "url" => "https://thibaultsan.com",
      "sameAs" => [
        "https://www.instagram.com/thibault__san/",
        "https://github.com/Thibault-Santonja",
        "https://www.linkedin.com/in/thibaultsantonja/"
      ],
      "jobTitle" => "Photographer & Software Engineer",
      "alumniOf" => "Université de Picardie Jules Verne"
    }
  end

  @doc """
  Generates Schema.org WebSite schema with search action.
  """
  def website_schema do
    schema = %{
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => "Thibault Santonja Photography",
      "alternateName" => "Thibault San Photography",
      "url" => "https://thibaultsan.com",
      "description" =>
        "Photography portfolio specializing in reenactment, concerts, weddings, and street photography",
      "author" => photographer_schema(),
      "inLanguage" => ["fr-FR", "en-US"]
    }

    Jason.encode!(schema)
  end

  @doc """
  Generates Schema.org BreadcrumbList for navigation.

  ## Parameters
  - `breadcrumbs` - List of %{name: "Name", url: "https://..."} maps

  ## Example
      breadcrumbs = [
        %{name: "Home", url: "https://photo.thibaultsan.com"},
        %{name: "Gallery", url: "https://photo.thibaultsan.com/gallery"},
        %{name: "Album Title", url: "https://photo.thibaultsan.com/album-slug"}
      ]
      breadcrumb_schema(breadcrumbs)
  """
  def breadcrumb_schema(breadcrumbs) do
    items =
      breadcrumbs
      |> Enum.with_index(1)
      |> Enum.map(fn {crumb, position} ->
        %{
          "@type" => "ListItem",
          "position" => position,
          "name" => crumb.name,
          "item" => crumb.url
        }
      end)

    schema = %{
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => items
    }

    Jason.encode!(schema)
  end

  @doc """
  Generates Schema.org ProfessionalService for AMVCC medieval reenactment.
  """
  def professional_service_schema do
    schema = %{
      "@context" => "https://schema.org",
      "@type" => "ProfessionalService",
      "name" => "La Seigneurie de Coucy - AMVCC",
      "alternateName" => "Association pour la Mise en Valeur du Château de Coucy",
      "description" =>
        "Reconstitution historique médiévale du XIVe siècle - Animations, spectacles et médiation culturelle",
      "url" => "https://amvcc.thibaultsan.com",
      "areaServed" => [
        %{
          "@type" => "Country",
          "name" => "France"
        },
        %{
          "@type" => "Country",
          "name" => "Belgium"
        },
        %{
          "@type" => "Country",
          "name" => "Switzerland"
        }
      ],
      "serviceType" => "Historical Reenactment & Medieval Animation",
      "address" => %{
        "@type" => "PostalAddress",
        "streetAddress" => "7-9 rue du Pot d'Etain",
        "addressLocality" => "Coucy-le-Château-Auffrique",
        "postalCode" => "02380",
        "addressCountry" => "FR"
      },
      "geo" => %{
        "@type" => "GeoCoordinates",
        "latitude" => 49.5172,
        "longitude" => 3.3172
      },
      "member" => photographer_schema()
    }

    Jason.encode!(schema)
  end

  @doc """
  Generates an Article schema for blog posts.

  ## Parameters
  - `title` - Article title
  - `description` - Article description
  - `url` - Full URL of the article
  - `published_date` - DateTime when published
  """
  def article_schema(title, description, url, published_date) do
    schema = %{
      "@context" => "https://schema.org",
      "@type" => "TechArticle",
      "headline" => title,
      "description" => description,
      "url" => url,
      "datePublished" => format_date(published_date),
      "dateModified" => format_date(published_date),
      "author" => photographer_schema(),
      "publisher" => %{
        "@type" => "Person",
        "name" => "Thibault Santonja"
      },
      "inLanguage" => "fr-FR"
    }

    Jason.encode!(schema)
  end

  # Private helper functions

  defp build_image_url(file_path) do
    if String.starts_with?(file_path, "http") do
      file_path
    else
      "https://thibaultsan.com#{file_path}"
    end
  end

  defp format_date(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end

  defp format_date(%NaiveDateTime{} = naive) do
    naive
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp format_date(%Date{} = date) do
    Date.to_iso8601(date)
  end

  defp format_date(_), do: Date.utc_today() |> Date.to_iso8601()

  defp extract_year(%DateTime{} = datetime), do: datetime.year
  defp extract_year(%NaiveDateTime{} = naive), do: naive.year
  defp extract_year(_), do: Date.utc_today().year

  defp maybe_add_exif_data(schema, nil), do: schema

  defp maybe_add_exif_data(schema, exif_data) when is_map(exif_data) do
    # Add contentLocation if we have GPS or City data
    location = extract_content_location(exif_data)

    if location do
      Map.put(schema, "contentLocation", location)
    else
      schema
    end
  end

  defp extract_content_location(exif_data) do
    city = Map.get(exif_data, "City")
    state = Map.get(exif_data, "State") || Map.get(exif_data, "Province")
    country = Map.get(exif_data, "Country")

    cond do
      city && country ->
        %{
          "@type" => "Place",
          "name" => city,
          "address" => %{
            "@type" => "PostalAddress",
            "addressLocality" => city,
            "addressRegion" => state,
            "addressCountry" => country
          }
        }

      country ->
        %{
          "@type" => "Country",
          "name" => country
        }

      true ->
        nil
    end
  end
end
