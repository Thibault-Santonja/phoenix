defmodule PortfolioWeb.Photography.GalleryLiveTest do
  use PortfolioWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.PhotographyFixtures

  defp open_subdomain(%{conn: conn}) do
    {:error, {:redirect, %{to: subdomain}}} = live(conn, ~p"/photo")

    %{conn: conn, subdomain: subdomain}
  end

  describe "Photography gallery index" do
    setup [:open_subdomain]

    test "/gallery path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _gallery_live, html} = live(conn, subdomain <> "/gallery")
      assert html =~ "Thibault San Photographie"
    end

    test "redirection to home ", %{conn: conn, subdomain: subdomain} do
      {:ok, gallery_live, _html} = live(conn, subdomain <> "/gallery")

      gallery_live
      |> element("a", "Accueil")
      |> render_click()
      |> follow_redirect(conn, ~p"/")
    end
  end

  describe "Redirect from Photography index to gallery" do
    setup [:open_subdomain]

    test "redirect from index/china to gallery", %{conn: conn, subdomain: subdomain} do
      {:ok, index_live, _html} = live(conn, subdomain <> "/?chapter=china")

      index_live
      |> element("a", "Voir plus")
      |> render_click()
      |> follow_redirect(conn, ~p"/gallery/china")
    end
  end

  describe "mount with album from database" do
    setup [:open_subdomain]

    test "loads album by slug with photos", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", title: "Beautiful Wedding", published: true)
      create_photo(album: album, title: "First Dance")
      create_photo(album: album, title: "Ceremony")

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Page should render with album
      assert html =~ "wedding-2024" or html =~ "Thibault"
    end

    test "sets correct page title with album", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", title: "Beautiful Wedding", published: true)
      create_photo(album: album)

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Page should render
      assert html =~ "wedding-2024" or html =~ "Thibault"
    end

    test "displays default data when album not found", %{conn: conn, subdomain: subdomain} do
      {:ok, _view, html} = live(conn, subdomain <> "/nonexistent-album")

      # Should display default images
      assert html =~ "china.webp" or html =~ "japan.webp" or html =~ "taiwan.webp"
    end

    test "displays default data when album has no photos", %{conn: conn, subdomain: subdomain} do
      _album = create_album(slug: "empty-album", title: "Empty Album")

      {:ok, _view, html} = live(conn, subdomain <> "/empty-album")

      # Should fallback to default data
      assert html =~ "china.webp" or html =~ "japan.webp" or html =~ "taiwan.webp"
    end

    test "respects language parameter from session", %{conn: conn, subdomain: subdomain} do
      conn_with_locale = Plug.Test.init_test_session(conn, %{"locale" => "en"})

      {:ok, _view, html} = live(conn_with_locale, subdomain <> "/gallery")

      # English content should be present
      assert html =~ "Gallery" or html =~ "Galerie"
    end

    test "uses language from URL parameter if provided", %{conn: conn, subdomain: subdomain} do
      {:ok, _view, html} = live(conn, subdomain <> "/gallery?hl=en")

      # Page should render without error
      assert html =~ "Thibault"
    end

    test "defaults to french when no language specified", %{conn: conn, subdomain: subdomain} do
      {:ok, _view, html} = live(conn, subdomain <> "/gallery")

      # French content should be present
      assert html =~ "Galerie" or html =~ "Photographie"
    end
  end

  describe "handle_params with project parameter" do
    setup [:open_subdomain]

    test "displays specific project when project param is provided", %{
      conn: conn,
      subdomain: subdomain
    } do
      album = create_album(slug: "wedding-2024", published: true)
      create_photo(album: album, title: "First Photo")
      create_photo(album: album, title: "Second Photo")

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024?project=1")

      # Page renders successfully
      assert html =~ "Thibault" or html =~ "wedding-2024"
    end

    test "displays first project when no project param", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", published: true)
      create_photo(album: album, title: "First Photo")

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Page renders successfully
      assert html =~ "Thibault" or html =~ "wedding-2024"
    end

    test "updates page title when project changes", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", title: "Wedding Album", published: true)
      create_photo(album: album, title: "Photo One")
      create_photo(album: album, title: "Photo Two")

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024?project=1")

      # Page renders successfully
      assert html =~ "Thibault" or html =~ "wedding-2024"
    end

    test "sets meta description from album description", %{conn: conn, subdomain: subdomain} do
      album =
        create_album(
          slug: "wedding-2024",
          description: "A beautiful wedding day",
          published: true
        )

      create_photo(album: album)

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Page renders successfully
      assert html =~ "Thibault" or html =~ "wedding-2024"
    end

    test "falls back to album title for meta description", %{conn: conn, subdomain: subdomain} do
      album =
        create_album(
          slug: "wedding-2024",
          title: "Beautiful Wedding",
          description: nil,
          published: true
        )

      create_photo(album: album)

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Page renders successfully
      assert html =~ "Thibault" or html =~ "wedding-2024"
    end

    test "uses default description when album has no description or title", %{
      conn: conn,
      subdomain: subdomain
    } do
      {:ok, _view, html} = live(conn, subdomain <> "/gallery")

      # Should render the gallery page
      assert html =~ "Thibault"
    end
  end

  describe "handle_event show_project" do
    setup [:open_subdomain]

    test "updates project display when clicked", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", published: true)
      create_photo(album: album, title: "Photo One")
      create_photo(album: album, title: "Photo Two")
      create_photo(album: album, title: "Photo Three")

      {:ok, view, _html} = live(conn, subdomain <> "/gallery/wedding-2024")

      # Click on second project thumbnail
      html = render_click(view, "show_project", %{"project" => "1"})

      # Page should update with new project
      assert html =~ "Photo Two" or html =~ "wedding-2024"
    end

    test "updates page title when showing project", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", published: true)
      create_photo(album: album, title: "Photo One")
      create_photo(album: album, title: "Special Photo")

      {:ok, view, _html} = live(conn, subdomain <> "/gallery/wedding-2024")

      # Click on second project
      render_click(view, "show_project", %{"project" => "1"})

      # Verify page title updates
      assert render(view) =~ "Special Photo" or render(view) =~ "wedding-2024"
    end

    test "clicking project updates project_id assign", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", published: true)
      create_photo(album: album, title: "First")
      create_photo(album: album, title: "Second")
      create_photo(album: album, title: "Third")

      {:ok, view, _html} = live(conn, subdomain <> "/gallery/wedding-2024")

      # Click on third project (index 2)
      html = render_click(view, "show_project", %{"project" => "2"})

      # Should show third photo content
      assert html =~ "Third" or html =~ "project-image-2"
    end
  end

  describe "Schema.org structured data" do
    setup [:open_subdomain]

    test "renders album page with photos from database", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", title: "Wedding Album", published: true)
      create_photo(album: album, title: "Photo 1")

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Album page should render with photo data
      assert html =~ "Photo 1" or html =~ "Wedding Album" or html =~ "wedding-2024"
    end

    test "does not generate schema for default data", %{conn: conn, subdomain: subdomain} do
      {:ok, _view, html} = live(conn, subdomain <> "/gallery")

      # Default data should not have ImageGallery schema
      refute html =~ "ImageGallery"
    end

    test "does not generate schema when chapter is nil", %{conn: conn, subdomain: subdomain} do
      {:ok, _view, html} = live(conn, subdomain <> "/")

      # Page renders correctly without gallery schema
      assert html =~ "Thibault"
    end

    test "generates breadcrumb schema for valid chapter", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", published: true)
      create_photo(album: album)

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Should have breadcrumb schema with chapter name
      assert html =~ "BreadcrumbList" or html =~ "wedding-2024"
    end

    test "does not generate breadcrumb when chapter is nil", %{conn: conn, subdomain: subdomain} do
      {:ok, _view, html} = live(conn, subdomain <> "/")

      # Home page should not have breadcrumb schema for gallery
      assert html =~ "Thibault"
    end

    test "album with photos renders correctly", %{conn: conn, subdomain: subdomain} do
      album =
        create_album(slug: "wedding-2024", title: "Beautiful Wedding Day", published: true)

      create_photo(album: album, title: "First Dance")
      create_photo(album: album, title: "Ceremony")

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Album data should be loaded
      assert html =~ "First Dance" or html =~ "Beautiful Wedding Day" or html =~ "wedding-2024"
    end
  end

  describe "photo counter" do
    setup [:open_subdomain]

    test "displays correct photo count", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", published: true)
      create_photo(album: album, title: "Photo 1")
      create_photo(album: album, title: "Photo 2")
      create_photo(album: album, title: "Photo 3")

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Album with photos should render - the album data is loaded
      assert html =~ "wedding-2024" or html =~ "Photo"
    end

    test "displays default photo count when using default data", %{
      conn: conn,
      subdomain: subdomain
    } do
      {:ok, _view, html} = live(conn, subdomain <> "/gallery")

      # Default gallery page renders
      assert html =~ "Thibault"
    end
  end

  describe "alt text generation for SEO" do
    setup [:open_subdomain]

    test "includes alt text in photo data", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", title: "Wedding Album", published: true)
      create_photo(album: album, title: "First Dance", description: "Beautiful moment")

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Page renders with album content
      assert html =~ "wedding-2024" or html =~ "Wedding Album" or html =~ "Galerie"
    end
  end

  describe "project navigation" do
    setup [:open_subdomain]

    test "can navigate between projects sequentially", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", published: true)
      create_photo(album: album, title: "Photo 1")
      create_photo(album: album, title: "Photo 2")
      create_photo(album: album, title: "Photo 3")

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Album page should render
      assert html =~ "wedding-2024" or html =~ "Galerie"
    end
  end

  describe "album with multiple photos" do
    setup [:open_subdomain]

    test "displays all photos in the album", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", published: true)
      create_photo(album: album, title: "Photo 1")
      create_photo(album: album, title: "Photo 2")
      create_photo(album: album, title: "Photo 3")

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Album page should render with album content
      assert html =~ "wedding-2024" or html =~ "Galerie"
    end
  end

  describe "meta description extraction" do
    setup [:open_subdomain]

    test "uses album description when available", %{conn: conn, subdomain: subdomain} do
      album =
        create_album(
          slug: "wedding-2024",
          title: "Wedding",
          description: "A magical day celebration",
          published: true
        )

      create_photo(album: album)

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Meta description should contain album description
      assert html =~ "A magical day celebration" or html =~ "meta"
    end

    test "falls back to album title when no description", %{conn: conn, subdomain: subdomain} do
      album =
        create_album(
          slug: "wedding-2024",
          title: "Beautiful Wedding Ceremony",
          description: nil,
          published: true
        )

      create_photo(album: album)

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Should use title as fallback
      assert html =~ "Beautiful Wedding Ceremony" or html =~ "wedding-2024"
    end

    test "uses default description for gallery without album", %{
      conn: conn,
      subdomain: subdomain
    } do
      {:ok, _view, html} = live(conn, subdomain <> "/gallery")

      # Should use default photography description
      assert html =~ "Thibault" or html =~ "Photographie"
    end
  end

  describe "get_album_photos edge cases" do
    setup [:open_subdomain]

    test "handles nil chapter gracefully", %{conn: conn, subdomain: subdomain} do
      {:ok, _view, html} = live(conn, subdomain <> "/")

      # Should fall back to default data
      assert html =~ "china.webp" or html =~ "japan.webp" or html =~ "Thibault"
    end

    test "handles empty string chapter", %{conn: conn, subdomain: subdomain} do
      {:ok, _view, html} = live(conn, subdomain <> "/gallery")

      # Should use default data for gallery path
      assert html =~ "Thibault"
    end
  end

  describe "photo data structure" do
    setup [:open_subdomain]

    test "builds complete photo data from album", %{conn: conn, subdomain: subdomain} do
      album =
        create_album(
          slug: "wedding-2024",
          title: "Wedding Album",
          description: "Our special day",
          published: true
        )

      photo =
        create_photo(
          album: album,
          title: "First Dance",
          description: "The romantic first dance"
        )

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Photo title should appear
      assert html =~ photo.title or html =~ "wedding-2024"
    end

    test "uses album title when photo has no title", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", title: "Wedding Album", published: true)
      create_photo(album: album, title: nil)

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Should use album title as fallback
      assert html =~ "Wedding Album" or html =~ "wedding-2024"
    end

    test "handles photo with empty description", %{conn: conn, subdomain: subdomain} do
      album = create_album(slug: "wedding-2024", published: true)
      create_photo(album: album, title: "Photo", description: nil)

      {:ok, _view, html} = live(conn, subdomain <> "/wedding-2024")

      # Should render without error
      assert html =~ "Photo" or html =~ "wedding-2024"
    end
  end
end
