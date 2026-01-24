defmodule PortfolioWeb.SEO.SchemaHelpersTest do
  use ExUnit.Case, async: true

  alias PortfolioWeb.SEO.SchemaHelpers

  describe "photographer_schema/0" do
    test "returns valid Person schema" do
      schema = SchemaHelpers.photographer_schema()

      assert schema["@type"] == "Person"
      assert schema["name"] == "Thibault Santonja"
      assert schema["url"] == "https://thibaultsan.com"
    end

    test "includes social media links in sameAs" do
      schema = SchemaHelpers.photographer_schema()

      assert is_list(schema["sameAs"])
      assert schema["sameAs"] != []
    end

    test "includes job title" do
      schema = SchemaHelpers.photographer_schema()

      assert schema["jobTitle"] == "Photographer & Software Engineer"
    end
  end

  describe "website_schema/0" do
    test "returns valid JSON-LD string" do
      json = SchemaHelpers.website_schema()

      assert is_binary(json)
      assert {:ok, schema} = Jason.decode(json)
      assert schema["@context"] == "https://schema.org"
      assert schema["@type"] == "WebSite"
    end

    test "includes required WebSite fields" do
      {:ok, schema} = Jason.decode(SchemaHelpers.website_schema())

      assert schema["name"] == "Thibault Santonja Photography"
      assert schema["url"] == "https://thibaultsan.com"
      assert is_binary(schema["description"])
    end

    test "includes author reference" do
      {:ok, schema} = Jason.decode(SchemaHelpers.website_schema())

      assert schema["author"]["@type"] == "Person"
      assert schema["author"]["name"] == "Thibault Santonja"
    end

    test "includes multiple languages" do
      {:ok, schema} = Jason.decode(SchemaHelpers.website_schema())

      assert is_list(schema["inLanguage"])
      assert "fr-FR" in schema["inLanguage"]
      assert "en-US" in schema["inLanguage"]
    end
  end

  describe "breadcrumb_schema/1" do
    test "returns valid JSON-LD for single breadcrumb" do
      breadcrumbs = [%{name: "Home", url: "https://example.com"}]
      json = SchemaHelpers.breadcrumb_schema(breadcrumbs)

      assert {:ok, schema} = Jason.decode(json)
      assert schema["@type"] == "BreadcrumbList"
      assert length(schema["itemListElement"]) == 1
    end

    test "returns valid JSON-LD for multiple breadcrumbs" do
      breadcrumbs = [
        %{name: "Home", url: "https://example.com"},
        %{name: "Gallery", url: "https://example.com/gallery"},
        %{name: "Album", url: "https://example.com/gallery/album"}
      ]

      json = SchemaHelpers.breadcrumb_schema(breadcrumbs)
      {:ok, schema} = Jason.decode(json)

      assert length(schema["itemListElement"]) == 3
    end

    test "assigns correct positions to breadcrumbs" do
      breadcrumbs = [
        %{name: "Home", url: "https://example.com"},
        %{name: "Gallery", url: "https://example.com/gallery"}
      ]

      json = SchemaHelpers.breadcrumb_schema(breadcrumbs)
      {:ok, schema} = Jason.decode(json)

      [first, second] = schema["itemListElement"]
      assert first["position"] == 1
      assert second["position"] == 2
    end

    test "includes correct ListItem type" do
      breadcrumbs = [%{name: "Home", url: "https://example.com"}]
      json = SchemaHelpers.breadcrumb_schema(breadcrumbs)
      {:ok, schema} = Jason.decode(json)

      [item] = schema["itemListElement"]
      assert item["@type"] == "ListItem"
      assert item["name"] == "Home"
      assert item["item"] == "https://example.com"
    end

    test "handles empty breadcrumbs list" do
      json = SchemaHelpers.breadcrumb_schema([])
      {:ok, schema} = Jason.decode(json)

      assert schema["itemListElement"] == []
    end
  end

  describe "professional_service_schema/0" do
    test "returns valid JSON-LD string" do
      json = SchemaHelpers.professional_service_schema()

      assert is_binary(json)
      assert {:ok, schema} = Jason.decode(json)
      assert schema["@context"] == "https://schema.org"
      assert schema["@type"] == "ProfessionalService"
    end

    test "includes AMVCC organization details" do
      {:ok, schema} = Jason.decode(SchemaHelpers.professional_service_schema())

      assert schema["name"] == "La Seigneurie de Coucy - AMVCC"
      assert is_binary(schema["description"])
    end

    test "includes address information" do
      {:ok, schema} = Jason.decode(SchemaHelpers.professional_service_schema())

      assert schema["address"]["@type"] == "PostalAddress"
      assert schema["address"]["addressLocality"] == "Coucy-le-Château-Auffrique"
      assert schema["address"]["addressCountry"] == "FR"
    end

    test "includes geo coordinates" do
      {:ok, schema} = Jason.decode(SchemaHelpers.professional_service_schema())

      assert schema["geo"]["@type"] == "GeoCoordinates"
      assert is_number(schema["geo"]["latitude"])
      assert is_number(schema["geo"]["longitude"])
    end

    test "includes multiple served areas" do
      {:ok, schema} = Jason.decode(SchemaHelpers.professional_service_schema())

      assert is_list(schema["areaServed"])
      countries = Enum.map(schema["areaServed"], & &1["name"])
      assert "France" in countries
    end
  end

  describe "article_schema/4" do
    test "returns valid JSON-LD for article" do
      json =
        SchemaHelpers.article_schema(
          "Test Article",
          "Article description",
          "https://example.com/article",
          DateTime.utc_now()
        )

      assert {:ok, schema} = Jason.decode(json)
      assert schema["@type"] == "TechArticle"
      assert schema["headline"] == "Test Article"
    end

    test "includes author and publisher" do
      json =
        SchemaHelpers.article_schema(
          "Test",
          "Desc",
          "https://example.com",
          DateTime.utc_now()
        )

      {:ok, schema} = Jason.decode(json)

      assert schema["author"]["@type"] == "Person"
      assert schema["publisher"]["@type"] == "Person"
    end

    test "formats dates correctly" do
      datetime = ~U[2024-06-15 10:30:00Z]

      json =
        SchemaHelpers.article_schema(
          "Test",
          "Desc",
          "https://example.com",
          datetime
        )

      {:ok, schema} = Jason.decode(json)

      assert schema["datePublished"] == "2024-06-15T10:30:00Z"
      assert schema["dateModified"] == "2024-06-15T10:30:00Z"
    end

    test "includes correct language" do
      json =
        SchemaHelpers.article_schema(
          "Test",
          "Desc",
          "https://example.com",
          DateTime.utc_now()
        )

      {:ok, schema} = Jason.decode(json)

      assert schema["inLanguage"] == "fr-FR"
    end
  end

  describe "faq_schema/1" do
    test "returns valid JSON-LD for single FAQ" do
      faqs = [%{question: "What is Elixir?", answer: "A functional language."}]
      json = SchemaHelpers.faq_schema(faqs)

      assert {:ok, schema} = Jason.decode(json)
      assert schema["@type"] == "FAQPage"
      assert length(schema["mainEntity"]) == 1
    end

    test "returns valid JSON-LD for multiple FAQs" do
      faqs = [
        %{question: "Question 1?", answer: "Answer 1"},
        %{question: "Question 2?", answer: "Answer 2"},
        %{question: "Question 3?", answer: "Answer 3"}
      ]

      json = SchemaHelpers.faq_schema(faqs)
      {:ok, schema} = Jason.decode(json)

      assert length(schema["mainEntity"]) == 3
    end

    test "structures Question and Answer correctly" do
      faqs = [%{question: "Test question?", answer: "Test answer."}]
      json = SchemaHelpers.faq_schema(faqs)
      {:ok, schema} = Jason.decode(json)

      [question] = schema["mainEntity"]
      assert question["@type"] == "Question"
      assert question["name"] == "Test question?"
      assert question["acceptedAnswer"]["@type"] == "Answer"
      assert question["acceptedAnswer"]["text"] == "Test answer."
    end

    test "handles empty FAQ list" do
      json = SchemaHelpers.faq_schema([])
      {:ok, schema} = Jason.decode(json)

      assert schema["mainEntity"] == []
    end
  end

  describe "how_to_schema/4" do
    test "returns valid JSON-LD for how-to guide" do
      steps = [
        %{name: "Step 1", text: "Do something"},
        %{name: "Step 2", text: "Do something else"}
      ]

      json = SchemaHelpers.how_to_schema("Guide Title", "Guide description", steps)

      assert {:ok, schema} = Jason.decode(json)
      assert schema["@type"] == "HowTo"
      assert schema["name"] == "Guide Title"
    end

    test "assigns correct positions to steps" do
      steps = [
        %{name: "First", text: "First step"},
        %{name: "Second", text: "Second step"},
        %{name: "Third", text: "Third step"}
      ]

      json = SchemaHelpers.how_to_schema("Guide", "Desc", steps)
      {:ok, schema} = Jason.decode(json)

      positions = Enum.map(schema["step"], & &1["position"])
      assert positions == [1, 2, 3]
    end

    test "includes HowToStep type for each step" do
      steps = [%{name: "Step", text: "Text"}]
      json = SchemaHelpers.how_to_schema("Guide", "Desc", steps)
      {:ok, schema} = Jason.decode(json)

      [step] = schema["step"]
      assert step["@type"] == "HowToStep"
      assert step["name"] == "Step"
      assert step["text"] == "Text"
    end

    test "includes total time when provided" do
      steps = [%{name: "Step", text: "Text"}]
      json = SchemaHelpers.how_to_schema("Guide", "Desc", steps, "PT30M")
      {:ok, schema} = Jason.decode(json)

      assert schema["totalTime"] == "PT30M"
    end

    test "omits total time when nil" do
      steps = [%{name: "Step", text: "Text"}]
      json = SchemaHelpers.how_to_schema("Guide", "Desc", steps, nil)
      {:ok, schema} = Jason.decode(json)

      refute Map.has_key?(schema, "totalTime")
    end

    test "handles empty steps list" do
      json = SchemaHelpers.how_to_schema("Guide", "Desc", [])
      {:ok, schema} = Jason.decode(json)

      assert schema["step"] == []
    end
  end

  describe "image_gallery_schema/3" do
    setup do
      album = %{
        title: "Test Album",
        description: "Test description",
        inserted_at: ~U[2024-01-15 10:00:00Z],
        updated_at: ~U[2024-06-20 15:30:00Z]
      }

      photo = %{
        file_path: "/images/photo1.jpg",
        title: "Photo Title",
        description: "Photo description",
        inserted_at: ~U[2024-01-10 08:00:00Z],
        exif_data: nil
      }

      {:ok, album: album, photo: photo}
    end

    test "returns valid JSON-LD for image gallery", %{album: album, photo: photo} do
      json = SchemaHelpers.image_gallery_schema(album, [photo], "https://example.com/album")

      assert {:ok, schema} = Jason.decode(json)
      assert schema["@type"] == "ImageGallery"
      assert schema["name"] == "Test Album"
    end

    test "includes album metadata", %{album: album, photo: photo} do
      json = SchemaHelpers.image_gallery_schema(album, [photo], "https://example.com/album")
      {:ok, schema} = Jason.decode(json)

      assert schema["description"] == "Test description"
      assert schema["url"] == "https://example.com/album"
    end

    test "formats dates correctly", %{album: album, photo: photo} do
      json = SchemaHelpers.image_gallery_schema(album, [photo], "https://example.com/album")
      {:ok, schema} = Jason.decode(json)

      assert schema["datePublished"] == "2024-01-15T10:00:00Z"
      assert schema["dateModified"] == "2024-06-20T15:30:00Z"
    end

    test "includes author reference", %{album: album, photo: photo} do
      json = SchemaHelpers.image_gallery_schema(album, [photo], "https://example.com/album")
      {:ok, schema} = Jason.decode(json)

      assert schema["author"]["@type"] == "Person"
      assert schema["author"]["name"] == "Thibault Santonja"
    end

    test "includes image objects for photos", %{album: album, photo: photo} do
      json = SchemaHelpers.image_gallery_schema(album, [photo], "https://example.com/album")
      {:ok, schema} = Jason.decode(json)

      assert length(schema["image"]) == 1
      [image] = schema["image"]
      assert image["@type"] == "ImageObject"
    end

    test "handles multiple photos", %{album: album, photo: photo} do
      photos = [photo, %{photo | title: "Photo 2"}, %{photo | title: "Photo 3"}]
      json = SchemaHelpers.image_gallery_schema(album, photos, "https://example.com/album")
      {:ok, schema} = Jason.decode(json)

      assert length(schema["image"]) == 3
    end

    test "handles empty photos list", %{album: album} do
      json = SchemaHelpers.image_gallery_schema(album, [], "https://example.com/album")
      {:ok, schema} = Jason.decode(json)

      assert schema["image"] == []
    end

    test "uses album title as fallback for nil description", %{photo: photo} do
      album = %{
        title: "Album Title",
        description: nil,
        inserted_at: DateTime.utc_now(),
        updated_at: nil
      }

      json = SchemaHelpers.image_gallery_schema(album, [photo], "https://example.com")
      {:ok, schema} = Jason.decode(json)

      assert schema["description"] == "Album Title"
    end
  end

  describe "image_object_schema/2" do
    setup do
      album = %{
        title: "Album",
        description: "Album description"
      }

      photo = %{
        file_path: "/images/photo.jpg",
        title: "Photo Title",
        description: "Photo description",
        inserted_at: ~U[2024-05-20 14:00:00Z],
        exif_data: nil
      }

      {:ok, album: album, photo: photo}
    end

    test "returns valid ImageObject schema", %{album: album, photo: photo} do
      schema = SchemaHelpers.image_object_schema(photo, album)

      assert schema["@type"] == "ImageObject"
      assert schema["name"] == "Photo Title"
    end

    test "builds full content URL for relative paths", %{album: album, photo: photo} do
      schema = SchemaHelpers.image_object_schema(photo, album)

      assert schema["contentUrl"] == "https://thibaultsan.com/images/photo.jpg"
    end

    test "preserves full URL for absolute paths", %{album: album} do
      photo = %{
        file_path: "https://cdn.example.com/photo.jpg",
        title: "Photo",
        description: nil,
        inserted_at: DateTime.utc_now(),
        exif_data: nil
      }

      schema = SchemaHelpers.image_object_schema(photo, album)

      assert schema["contentUrl"] == "https://cdn.example.com/photo.jpg"
    end

    test "uses album title as fallback for nil photo title", %{album: album} do
      photo = %{
        file_path: "/photo.jpg",
        title: nil,
        description: nil,
        inserted_at: DateTime.utc_now(),
        exif_data: nil
      }

      schema = SchemaHelpers.image_object_schema(photo, album)

      assert schema["name"] == "Album - Photo"
    end

    test "includes copyright information", %{album: album, photo: photo} do
      schema = SchemaHelpers.image_object_schema(photo, album)

      assert schema["copyrightHolder"]["@type"] == "Person"
      assert schema["copyrightYear"] == 2024
    end

    test "adds content location from EXIF City and Country", %{album: album} do
      photo = %{
        file_path: "/photo.jpg",
        title: "Photo",
        description: nil,
        inserted_at: DateTime.utc_now(),
        exif_data: %{"City" => "Paris", "Country" => "France", "State" => "Île-de-France"}
      }

      schema = SchemaHelpers.image_object_schema(photo, album)

      assert schema["contentLocation"]["@type"] == "Place"
      assert schema["contentLocation"]["name"] == "Paris"
      assert schema["contentLocation"]["address"]["addressLocality"] == "Paris"
      assert schema["contentLocation"]["address"]["addressCountry"] == "France"
    end

    test "adds content location with just country", %{album: album} do
      photo = %{
        file_path: "/photo.jpg",
        title: "Photo",
        description: nil,
        inserted_at: DateTime.utc_now(),
        exif_data: %{"Country" => "Japan"}
      }

      schema = SchemaHelpers.image_object_schema(photo, album)

      assert schema["contentLocation"]["@type"] == "Country"
      assert schema["contentLocation"]["name"] == "Japan"
    end

    test "handles EXIF data without location info", %{album: album} do
      photo = %{
        file_path: "/photo.jpg",
        title: "Photo",
        description: nil,
        inserted_at: DateTime.utc_now(),
        exif_data: %{"Camera" => "Canon EOS R5", "ISO" => "400"}
      }

      schema = SchemaHelpers.image_object_schema(photo, album)

      refute Map.has_key?(schema, "contentLocation")
    end
  end

  describe "date formatting" do
    test "formats DateTime correctly" do
      album = %{
        title: "Test",
        description: nil,
        inserted_at: ~U[2024-03-15 09:30:00Z],
        updated_at: nil
      }

      json = SchemaHelpers.image_gallery_schema(album, [], "https://example.com")
      {:ok, schema} = Jason.decode(json)

      assert schema["datePublished"] == "2024-03-15T09:30:00Z"
    end

    test "formats NaiveDateTime correctly" do
      album = %{
        title: "Test",
        description: nil,
        inserted_at: ~N[2024-03-15 09:30:00],
        updated_at: nil
      }

      json = SchemaHelpers.image_gallery_schema(album, [], "https://example.com")
      {:ok, schema} = Jason.decode(json)

      assert String.starts_with?(schema["datePublished"], "2024-03-15")
    end

    test "handles nil dates gracefully" do
      album = %{
        title: "Test",
        description: nil,
        inserted_at: nil,
        updated_at: nil
      }

      json = SchemaHelpers.image_gallery_schema(album, [], "https://example.com")
      {:ok, schema} = Jason.decode(json)

      assert is_binary(schema["datePublished"])
    end
  end
end
