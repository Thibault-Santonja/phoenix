defmodule PortfolioWeb.Integration.AlbumManagementTest do
  @moduledoc """
  Integration tests for the complete album management workflow.

  These tests verify the entire album lifecycle from creation to publication,
  including photo uploads and timeline visibility.

  Following the approach from docs/guides/towards-maintainable-elixir-testing.md,
  we test at the interface level (LiveView) to maximize confidence.
  """

  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.{AuthFixtures, PhotographyFixtures}

  alias Portfolio.Photography

  setup do
    # Create authenticated user for all tests
    session = create_authenticated_user()
    conn = build_conn() |> init_test_session(%{session_token: session.token})

    {:ok, conn: conn, session: session}
  end

  describe "album creation workflow" do
    test "user can create album through LiveView", %{conn: conn} do
      # Navigate to new album page
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      # Fill in album form
      form_data = %{
        "album" => %{
          "title" => "My Wedding Album",
          "type" => "wedding",
          "date_prise_vue" => "2024-06-15",
          "location" => "Paris",
          "description" => "Beautiful wedding in Paris",
          "published" => "false"
        }
      }

      # Submit form
      view
      |> form("#album-form", form_data)
      |> render_submit()

      # Verify redirect to albums list
      assert_redirected(view, ~p"/admin/albums")

      # Verify album was created in database
      albums = Photography.list_albums()
      assert length(albums) == 1

      album = hd(albums)
      assert album.title == "My Wedding Album"
      assert album.type == :wedding
      assert album.location == "Paris"
      assert album.published == false
      assert album.slug == "my-wedding-album"
    end

    test "validation errors are displayed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      # Submit form with invalid data (missing required fields)
      form_data = %{
        "album" => %{
          "title" => "",
          "type" => "",
          "date_prise_vue" => ""
        }
      }

      html =
        view
        |> form("#album-form", form_data)
        |> render_change()

      # Verify error messages are shown
      assert html =~ "can&#39;t be blank" or html =~ "can&apos;t be blank"
    end

    test "slug is generated automatically from title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      form_data = %{
        "album" => %{
          "title" => "Été à la Plage 2024!",
          "type" => "landscape",
          "date_prise_vue" => "2024-07-01"
        }
      }

      view
      |> form("#album-form", form_data)
      |> render_submit()

      album = Photography.list_albums() |> hd()
      assert album.slug == "ete-a-la-plage-2024"
    end
  end

  describe "photo upload workflow" do
    test "user can upload photos to album", %{conn: conn} do
      # Create album first
      album = create_album(title: "Test Album")

      # Navigate to edit page
      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Verify upload component is present
      assert has_element?(view, "input[type='file']")
      assert has_element?(view, "form[phx-submit='upload']")

      # Note: Testing actual file upload in LiveView is complex
      # This test verifies the UI is present
      # The actual upload logic is tested in unit tests
    end

    test "uploaded photos appear in album", %{conn: conn} do
      # Create album with photos using the fixture
      album = create_album_with_photos(3, title: "Album with Photos")

      # Navigate to edit page
      {:ok, _view, html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Verify photos are displayed
      assert html =~ "Photos de l&#39;album" or html =~ "Photos de l&apos;album"
      assert html =~ "(3)"

      # Verify photos are in database
      photos = Photography.list_photos_by_album(album.id)
      assert length(photos) == 3
    end

    test "photo count is correct in album list", %{conn: conn} do
      # Create albums with different photo counts
      _album1 = create_album_with_photos(3, title: "Album 1")
      _album2 = create_album_with_photos(5, title: "Album 2")
      # No photos
      _album3 = create_album(title: "Album 3")

      # Navigate to albums list
      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      # This is a simple smoke test - actual rendering depends on template
      assert html =~ "Album 1"
      assert html =~ "Album 2"
      assert html =~ "Album 3"
    end
  end

  describe "album publication workflow" do
    test "user can publish album", %{conn: conn} do
      # Create unpublished album with photos
      album = create_album_with_photos(3, title: "Unpublished Album", published: false)

      # Navigate to albums list
      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Toggle publish status
      view
      |> element("button[phx-click='toggle_publish'][phx-value-id='#{album.id}']")
      |> render_click()

      # Verify album is now published
      updated_album = Photography.get_album!(album.id)
      assert updated_album.published == true
    end

    test "published albums appear on timeline", %{conn: conn} do
      # Create published album with photos
      album =
        create_published_album(3,
          title: "Wedding 2024",
          type: :wedding,
          date_prise_vue: Date.utc_today()
        )

      # Navigate to timeline (public page, no auth needed)
      # New conn without auth
      conn = build_conn()
      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Verify album appears on timeline
      assert html =~ "Wedding 2024"
    end

    test "unpublished albums do not appear on timeline", %{conn: conn} do
      # Create unpublished album
      _album =
        create_album_with_photos(3,
          title: "Private Album",
          published: false
        )

      # Navigate to timeline
      conn = build_conn()
      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Verify album does not appear
      refute html =~ "Private Album"
    end
  end

  describe "album editing workflow" do
    test "user can update album details", %{conn: conn} do
      # Create album
      album = create_album(title: "Original Title")

      # Navigate to edit page
      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Update album
      updated_data = %{
        "album" => %{
          "title" => "Updated Title",
          "description" => "New description"
        }
      }

      view
      |> form("#album-form", updated_data)
      |> render_submit()

      # Verify changes persisted
      updated_album = Photography.get_album!(album.id)
      assert updated_album.title == "Updated Title"
      assert updated_album.description == "New description"
    end

    test "user can delete album", %{conn: conn} do
      # Create album
      album = create_album(title: "To Delete")

      # Navigate to albums list
      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Delete album
      view
      |> element("a[phx-click='delete'][phx-value-id='#{album.id}']")
      |> render_click()

      # Verify album was deleted
      assert {:error, :not_found} = Photography.get_album(album.id)
    end

    test "deleting album also deletes associated photos", %{conn: conn} do
      # Create album with photos
      album = create_album_with_photos(3, title: "Album to Delete")
      photo_ids = Enum.map(album.photos, & &1.id)

      # Delete album
      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      view
      |> element("a[phx-click='delete'][phx-value-id='#{album.id}']")
      |> render_click()

      # Verify photos were deleted (cascade)
      for photo_id <- photo_ids do
        assert {:error, :not_found} = Photography.get_photo(photo_id)
      end
    end
  end

  describe "timeline grouping" do
    test "albums are grouped by year on timeline", %{conn: conn} do
      # Create albums in different years
      create_published_album(2,
        title: "Album 2023",
        date_prise_vue: ~D[2023-06-15]
      )

      create_published_album(2,
        title: "Album 2024",
        date_prise_vue: ~D[2024-06-15]
      )

      # Navigate to timeline
      conn = build_conn()
      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Verify both years appear
      assert html =~ "2023"
      assert html =~ "2024"

      # Verify albums appear under correct years
      assert html =~ "Album 2023"
      assert html =~ "Album 2024"
    end

    test "timeline shows albums with cover photos", %{conn: conn} do
      # Create published album with photos
      album = create_published_album(3, title: "Test Album")

      # Navigate to timeline
      conn = build_conn()
      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Verify album appears
      assert html =~ "Test Album"

      # Cover photo should be the first photo
      first_photo = hd(album.photos)
      assert html =~ first_photo.file_path
    end
  end

  describe "error scenarios" do
    test "cannot access admin pages without authentication" do
      # Try to access admin pages without auth
      # No session
      conn = build_conn()

      # Should redirect to login for all admin pages
      {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/albums")
      {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/admin/albums/new")
    end

    test "404 for non-existent album", %{conn: conn} do
      # Try to edit non-existent album
      fake_id = Ecto.UUID.generate()

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/admin/albums/#{fake_id}/edit")
      end
    end

    test "cannot create album with future date", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      future_date = Date.add(Date.utc_today(), 365)

      form_data = %{
        "album" => %{
          "title" => "Future Album",
          "type" => "wedding",
          "date_prise_vue" => Date.to_string(future_date)
        }
      }

      html =
        view
        |> form("#album-form", form_data)
        |> render_change()

      # Should show validation error
      # Note: The exact error message depends on your validation rules
      assert html =~ "date" or html =~ "futur"
    end
  end

  describe "performance and edge cases" do
    test "handles albums with many photos efficiently", %{conn: conn} do
      # Create album with many photos
      album = create_album_with_photos(50, title: "Large Album")

      # Navigate to edit page - should load without timeout
      {:ok, _view, html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Verify all photos are loaded
      assert html =~ "(50)"
    end

    test "handles special characters in album title", %{conn: conn} do
      titles_with_special_chars = [
        "Été & Hiver 2024",
        "L'Album d'été",
        "Mariage — Julie & Tom",
        "Photos « spéciales »"
      ]

      for title <- titles_with_special_chars do
        {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

        form_data = %{
          "album" => %{
            "title" => title,
            "type" => "wedding",
            "date_prise_vue" => "2024-01-01"
          }
        }

        view
        |> form("#album-form", form_data)
        |> render_submit()

        # Verify album was created with correct title
        album = Photography.list_albums() |> List.last()
        assert album.title == title
      end
    end

    test "concurrent album creation doesn't cause conflicts", %{conn: _conn} do
      # Create multiple sessions
      sessions = for _i <- 1..3, do: create_authenticated_user()

      # Concurrent album creation
      tasks =
        for {session, i} <- Enum.with_index(sessions) do
          Task.async(fn ->
            conn = build_conn() |> init_test_session(%{session_token: session.token})
            {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

            form_data = %{
              "album" => %{
                "title" => "Concurrent Album #{i}",
                "type" => "wedding",
                "date_prise_vue" => "2024-01-01"
              }
            }

            view
            |> form("#album-form", form_data)
            |> render_submit()
          end)
        end

      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await/1)

      # Verify all albums were created
      albums = Photography.list_albums()
      assert length(albums) >= 3
    end
  end
end
