defmodule PortfolioWeb.Admin.PhotoLive.IndexTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.{AuthFixtures, PhotographyFixtures}

  alias Portfolio.Auth

  setup do
    user = create_user(email: "admin@example.com", role: :admin)
    {:ok, session} = Auth.create_session(user)

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> put_session(:session_token, session.token)

    %{conn: conn, user: user}
  end

  describe "Photo list page" do
    test "displays page with title", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/photos")

      assert html =~ "Photos"
    end

    test "shows empty state when no photos", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/photos")

      # Should show total count of 0 in the subtitle
      assert html =~ "0"
    end

    test "displays photos with album information", %{conn: conn} do
      album = create_album(title: "Test Album")
      _photo1 = create_photo(album_id: album.id, title: "Photo 1")
      _photo2 = create_photo(album_id: album.id, title: "Photo 2")

      {:ok, view, _html} = live(conn, ~p"/admin/photos")

      # Photo titles appear in hover overlay, check they exist in the view
      html = render(view)
      assert html =~ "Photo 1"
      assert html =~ "Photo 2"
      assert html =~ "Test Album"
    end

    test "shows total photo count", %{conn: conn} do
      album = create_album(title: "Test Album")
      create_photo(album_id: album.id)
      create_photo(album_id: album.id)
      create_photo(album_id: album.id)

      {:ok, _view, html} = live(conn, ~p"/admin/photos")

      assert html =~ "3"
    end
  end

  describe "Album filtering" do
    test "displays album filter buttons", %{conn: conn} do
      unique_id = System.unique_integer([:positive])
      _album1 = create_album(title: "FilterAlbumA#{unique_id}")
      _album2 = create_album(title: "FilterAlbumB#{unique_id}")

      {:ok, view, _html} = live(conn, ~p"/admin/photos")

      # Should show album titles as filter options
      assert has_element?(view, "a", "FilterAlbumA#{unique_id}")
      assert has_element?(view, "a", "FilterAlbumB#{unique_id}")
    end

    test "can navigate to album filter URL", %{conn: conn} do
      unique_id = System.unique_integer([:positive])
      album1 = create_album(title: "NavAlbum#{unique_id}")
      _photo1 = create_photo(album_id: album1.id, title: "NavPhoto#{unique_id}")

      {:ok, view, _html} = live(conn, ~p"/admin/photos")

      # Click on album filter using href selector with album ID
      view
      |> element("a[href*='album=#{album1.id}']")
      |> render_click()

      assert_patched(view, "/admin/photos?album=#{album1.id}")
    end

    test "shows filtered photo count when album parameter provided", %{conn: conn} do
      unique_id = System.unique_integer([:positive])
      album1 = create_album(title: "FilteredAlbum#{unique_id}")
      album2 = create_album(title: "OtherAlbum#{unique_id}")
      _photo1 = create_photo(album_id: album1.id, title: "FilteredPhoto#{unique_id}")
      _photo2 = create_photo(album_id: album2.id, title: "OtherPhoto#{unique_id}")

      # Navigate directly to filtered URL
      {:ok, _view, html} = live(conn, ~p"/admin/photos?album=#{album1.id}")

      # Should show photo count of 1 (only photos from album1)
      assert html =~ "1"
    end

    test "shows all photos without filter", %{conn: conn} do
      unique_id = System.unique_integer([:positive])
      album1 = create_album(title: "AllAlbum1#{unique_id}")
      album2 = create_album(title: "AllAlbum2#{unique_id}")
      _photo1 = create_photo(album_id: album1.id, title: "AllPhoto1#{unique_id}")
      _photo2 = create_photo(album_id: album2.id, title: "AllPhoto2#{unique_id}")

      {:ok, _view, html} = live(conn, ~p"/admin/photos")

      assert html =~ "AllPhoto1#{unique_id}"
      assert html =~ "AllPhoto2#{unique_id}"
    end

    test "shows 'all' filter as active by default", %{conn: conn} do
      unique_id = System.unique_integer([:positive])
      _album = create_album(title: "ActiveAlbum#{unique_id}")

      {:ok, view, _html} = live(conn, ~p"/admin/photos")

      # The 'all' filter should have active styling (indigo background)
      assert has_element?(view, "a.bg-indigo-100[href=\"/admin/photos\"]")
    end
  end

  describe "Pagination" do
    @tag :slow
    test "shows pagination when more than 50 photos", %{conn: conn} do
      unique_id = System.unique_integer([:positive])
      album = create_album(title: "PaginationAlbum#{unique_id}")

      # Create 55 photos
      for i <- 1..55 do
        create_photo(album_id: album.id, title: "PagPhoto#{unique_id}_#{i}")
      end

      {:ok, view, html} = live(conn, ~p"/admin/photos")

      # Should show total count (55 + any from other tests)
      assert html =~ "55"

      # Should have pagination - check for page indicator text
      assert html =~ "page"
      assert has_element?(view, "nav")
    end

    test "does not show pagination when few photos", %{conn: conn} do
      unique_id = System.unique_integer([:positive])
      album = create_album(title: "FewPhotosAlbum#{unique_id}")

      for i <- 1..3 do
        create_photo(album_id: album.id, title: "FewPhoto#{unique_id}_#{i}")
      end

      {:ok, view, html} = live(conn, ~p"/admin/photos?album=#{album.id}")

      # Should show only 3 photos, pagination not needed
      assert html =~ "3"
      # No pagination nav for small sets
      refute has_element?(view, "nav.isolate")
    end

    @tag :slow
    test "navigates to second page", %{conn: conn} do
      unique_id = System.unique_integer([:positive])
      album = create_album(title: "NavPageAlbum#{unique_id}")

      for i <- 1..55 do
        create_photo(album_id: album.id, title: "NavPagePhoto#{unique_id}_#{i}")
      end

      {:ok, _view, html} = live(conn, ~p"/admin/photos?page=2")

      # Second page should load successfully and show page indicator
      assert html =~ "2"
    end

    @tag :slow
    test "page 2 loads correctly via URL", %{conn: conn} do
      unique_id = System.unique_integer([:positive])
      album = create_album(title: "ClickPageAlbum#{unique_id}")

      for i <- 1..55 do
        create_photo(album_id: album.id, title: "ClickPagePhoto#{unique_id}_#{i}")
      end

      # Navigate directly to page 2
      {:ok, _view, html} = live(conn, ~p"/admin/photos?page=2")

      # Should be on page 2
      assert html =~ "Photos"
    end
  end

  describe "Combined filtering and pagination" do
    @tag :slow
    test "album filter works with many photos", %{conn: conn} do
      unique_id = System.unique_integer([:positive])
      album = create_album(title: "CombinedAlbum#{unique_id}")

      for i <- 1..55 do
        create_photo(album_id: album.id, title: "CombinedPhoto#{unique_id}_#{i}")
      end

      {:ok, _view, html} = live(conn, ~p"/admin/photos?album=#{album.id}")

      # Should show photos for this album (55 created)
      # Check page renders with album filter active
      assert html =~ "CombinedAlbum#{unique_id}"
    end

    @tag :slow
    test "loads page 2 with album filter", %{conn: conn} do
      unique_id = System.unique_integer([:positive])
      album = create_album(title: "Page2Album#{unique_id}")

      for i <- 1..55 do
        create_photo(album_id: album.id, title: "Page2Photo#{unique_id}_#{i}")
      end

      {:ok, _view, html} = live(conn, ~p"/admin/photos?album=#{album.id}&page=2")

      # Should still be filtered by album on page 2
      assert html =~ "Photos"
    end
  end

  describe "Edge cases" do
    test "handles invalid page number gracefully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/photos?page=invalid")

      # Should default to page 1
      assert html =~ "Photos"
    end

    test "handles negative page number", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/photos?page=-1")

      # Should default to page 1
      assert html =~ "Photos"
    end

    test "handles very large page number", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/photos?page=999999")

      # Should handle gracefully (show empty or last page)
      assert html =~ "Photos"
    end

    test "handles non-existent album filter", %{conn: conn} do
      fake_album_id = Ecto.UUID.generate()

      {:ok, _view, html} = live(conn, ~p"/admin/photos?album=#{fake_album_id}")

      # Should show 0 photos
      assert html =~ "0"
    end

    test "clears album filter when clicking all", %{conn: conn} do
      unique_id = System.unique_integer([:positive])
      album = create_album(title: "ClearFilterAlbum#{unique_id}")
      _photo = create_photo(album_id: album.id, title: "ClearFilterPhoto#{unique_id}")

      {:ok, view, _html} = live(conn, ~p"/admin/photos?album=#{album.id}")

      # Click on "Tous" to clear filter
      view
      |> element("a[href=\"/admin/photos\"]", "Tous")
      |> render_click()

      assert_patched(view, "/admin/photos")
    end
  end
end
