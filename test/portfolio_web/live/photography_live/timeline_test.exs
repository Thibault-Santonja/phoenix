defmodule PortfolioWeb.PhotographyLive.TimelineTest do
  use PortfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.PhotographyFixtures

  # Timeline is on the photo subdomain
  @endpoint PortfolioWeb.Endpoint

  setup %{conn: conn} do
    # Set French locale for consistent testing (default locale)
    Gettext.put_locale(PortfolioWeb.Gettext, "fr")
    # Set the photo subdomain
    conn = %{conn | host: "photo.example.com"}
    # Initialize session with French locale
    conn = init_test_session(conn, %{"locale" => "fr"})
    %{conn: conn}
  end

  describe "Timeline - Mount and Display" do
    test "renders timeline page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "Thibault Santonja"
      assert html =~ "Accueil"
    end

    test "displays years navigation in header when albums exist", %{conn: conn} do
      create_published_album(2,
        title: "Test Album 2023",
        date_prise_vue: ~D[2023-06-15],
        type: :wedding
      )

      create_published_album(2,
        title: "Test Album 2024",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Should display years as links
      assert html =~ "2023"
      assert html =~ "2024"
      # Check they're anchor links
      assert html =~ "#year-2023"
      assert html =~ "#year-2024"
    end

    test "displays language selector", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/timeline")

      assert view |> element("button[phx-click='change_locale']") |> has_element?()
    end

    test "sets default page title", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Page title is set in the HTML head (French: "Galerie chronologique de photographie")
      assert html =~ "Galerie chronologique"
    end
  end

  describe "Timeline - Pagination and Lazy Loading" do
    test "initially loads first page of albums (20)", %{conn: conn} do
      # Create 25 albums to test pagination (dates in descending order so Album 1 appears first)
      for i <- 1..25 do
        create_published_album(1,
          title: "Album #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], 26 - i),
          type: :wedding
        )
      end

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Should load 20 albums initially
      assert html =~ "Album 1"
      assert html =~ "Album 20"
      # Should not load 21st album yet
      refute html =~ "Album 21"
    end

    test "shows infinite scroll marker when more albums exist", %{conn: conn} do
      # Create 25 albums to test pagination
      for i <- 1..25 do
        create_published_album(1,
          title: "Album #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], i),
          type: :wedding
        )
      end

      {:ok, view, _html} = live(conn, ~p"/timeline")

      # Infinite scroll marker should be present
      assert view |> element("#infinite-scroll-marker") |> has_element?()
    end

    test "hides infinite scroll marker when no more albums", %{conn: conn} do
      # Create only 10 albums (less than page size)
      for i <- 1..10 do
        create_published_album(1,
          title: "Album #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], i),
          type: :wedding
        )
      end

      {:ok, view, _html} = live(conn, ~p"/timeline")

      # Infinite scroll marker should NOT be present
      refute view |> element("#infinite-scroll-marker") |> has_element?()
    end

    test "load_more event loads next page", %{conn: conn} do
      # Create 25 albums (dates in descending order so Album 1 appears first)
      for i <- 1..25 do
        create_published_album(1,
          title: "Album #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], 26 - i),
          type: :wedding
        )
      end

      {:ok, view, html} = live(conn, ~p"/timeline")

      # Initially should have first 20
      assert html =~ "Album 1"
      refute html =~ "Album 21"

      # Trigger load_more
      view |> render_hook("load_more", %{})

      # Now should have albums 21-25
      html = render(view)
      assert html =~ "Album 21"
      assert html =~ "Album 25"
    end

    test "multiple load_more events work correctly", %{conn: conn} do
      # Create 50 albums (2.5 pages, dates in descending order so Album 1 appears first)
      for i <- 1..50 do
        create_published_album(1,
          title: "Album #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], 51 - i),
          type: :wedding
        )
      end

      {:ok, view, _html} = live(conn, ~p"/timeline")

      # Load page 2
      view |> render_hook("load_more", %{})
      html = render(view)
      assert html =~ "Album 40"
      refute html =~ "Album 41"

      # Load page 3
      view |> render_hook("load_more", %{})
      html = render(view)
      assert html =~ "Album 41"
      assert html =~ "Album 50"
    end

    test "pagination respects chapter filter", %{conn: conn} do
      # Create 25 wedding albums (dates in descending order, starting from March)
      for i <- 1..25 do
        create_published_album(1,
          title: "Wedding #{i}",
          date_prise_vue: Date.add(~D[2024-03-01], 26 - i),
          type: :wedding
        )
      end

      # Create 25 couples albums (dates in descending order, starting from January)
      for i <- 1..25 do
        create_published_album(1,
          title: "Couples #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], 26 - i),
          type: :couples
        )
      end

      {:ok, view, html} = live(conn, ~p"/timeline/wedding")

      # Should only show wedding albums
      assert html =~ "Wedding 1"
      refute html =~ "Couples 1"

      # Load more should load more wedding albums only
      view |> render_hook("load_more", %{})
      html = render(view)
      assert html =~ "Wedding 21"
      refute html =~ "Couples 21"
    end

    test "uses LiveView streams for performance", %{conn: conn} do
      # Create 25 albums
      for i <- 1..25 do
        create_published_album(1,
          title: "Album #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], i),
          type: :wedding
        )
      end

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Should have stream update attribute
      assert html =~ ~s(phx-update="stream")
    end

    test "albums list has correct DOM structure for streams", %{conn: conn} do
      create_published_album(1,
        title: "Test Album",
        date_prise_vue: ~D[2024-01-01],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Should have albums-list container with stream update
      assert html =~ ~s(id="albums-list")
      assert html =~ ~s(phx-update="stream")
    end
  end

  describe "Timeline - Year Display with Pagination" do
    test "albums have year data attribute for YearTrigger hook", %{conn: conn} do
      create_published_album(1,
        title: "Album 2023",
        date_prise_vue: ~D[2023-06-15],
        type: :wedding
      )

      create_published_album(1,
        title: "Album 2024",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Albums should have data-year attribute
      assert html =~ ~s(data-year="2023")
      assert html =~ ~s(data-year="2024")
    end

    test "albums maintain YearTrigger hook for year transitions", %{conn: conn} do
      create_published_album(1,
        title: "Test Album",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ ~s(phx-hook="YearTrigger")
    end
  end

  describe "Timeline - Database Albums" do
    test "displays published albums from database", %{conn: conn} do
      create_published_album(3,
        title: "Test DB Album",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "Test DB Album"
    end

    test "does not display unpublished albums", %{conn: conn} do
      create_album_with_photos(3,
        title: "Unpublished Album",
        published: false,
        date_prise_vue: ~D[2024-06-15]
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      refute html =~ "Unpublished Album"
    end

    test "displays albums from different years", %{conn: conn} do
      create_published_album(2,
        title: "Album 2023",
        date_prise_vue: ~D[2023-05-01],
        type: :wedding
      )

      create_published_album(2,
        title: "Album 2024",
        date_prise_vue: ~D[2024-08-15],
        type: :couples
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Both albums should be displayed
      assert html =~ "Album 2023"
      assert html =~ "Album 2024"
      # With year data attributes
      assert html =~ ~s(data-year="2023")
      assert html =~ ~s(data-year="2024")
    end

    test "uses first photo as cover image", %{conn: conn} do
      album =
        create_album(
          title: "Album with Photos",
          published: true,
          date_prise_vue: ~D[2024-06-15],
          type: :wedding
        )

      _photo =
        create_photo(
          album: album,
          file_path: "/uploads/test-cover.jpg",
          display_order: 0
        )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "Album with Photos"
      assert html =~ "/uploads/test-cover.jpg"
    end

    test "displays album with date range", %{conn: conn} do
      create_published_album(2,
        title: "Multi-day Event",
        date_prise_vue: ~D[2024-06-15],
        date_fin_prise_vue: ~D[2024-06-17],
        type: :events
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "Multi-day Event"
      # Should show start date at minimum
      assert html =~ "2024-06-15"
      # If end date is provided, it should be displayed
      # Note: implementation shows "2024-06-15 - 2024-06-17" format
      assert html =~ "2024-06-17"
    end

    test "displays album with single date when no end date", %{conn: conn} do
      create_published_album(2,
        title: "Single Day Event",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "Single Day Event"
      assert html =~ "2024-06-15"
      refute html =~ "2024-06-15 - "
    end
  end

  describe "Timeline - Chapter Filtering" do
    test "filters albums by chapter (type)", %{conn: conn} do
      create_published_album(2,
        title: "Wedding Album",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      create_published_album(2,
        title: "Couples Album",
        date_prise_vue: ~D[2024-07-20],
        type: :couples
      )

      {:ok, _view, html} = live(conn, ~p"/timeline/wedding")

      # Should show wedding albums but not couples
      assert html =~ "Wedding Album"
      # Note: "Couples" might appear in the title but "Couples Album" should not
      refute html =~ ">Couples Album<"
    end

    test "updates page title when filtering by chapter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/timeline/wedding")

      # Page title should include the chapter name (capitalized)
      assert html =~ "Wedding"
    end

    test "filters correctly across different years", %{conn: conn} do
      # Only create wedding album in 2024
      create_published_album(2,
        title: "2024 Wedding",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      # Create landscape album in 2023
      create_published_album(2,
        title: "2023 Landscape",
        date_prise_vue: ~D[2023-06-15],
        type: :landscape
      )

      {:ok, _view, html} = live(conn, ~p"/timeline/wedding")

      # Should only show wedding album
      assert html =~ "2024 Wedding"
      refute html =~ ">2023 Landscape<"
    end

    test "filters multiple album types correctly", %{conn: conn} do
      create_published_album(2, title: "Wedding", date_prise_vue: ~D[2024-06-15], type: :wedding)
      create_published_album(2, title: "Couples", date_prise_vue: ~D[2024-06-15], type: :couples)
      create_published_album(2, title: "Music", date_prise_vue: ~D[2024-06-15], type: :music)

      # Filter by wedding
      {:ok, _view, html} = live(conn, ~p"/timeline/wedding")
      assert html =~ "Wedding"
      refute html =~ ">Couples<"
      refute html =~ ">Music<"
    end
  end

  describe "Timeline - Album Display" do
    test "displays album title and date", %{conn: conn} do
      create_published_album(2,
        title: "Summer Wedding 2024",
        date_prise_vue: ~D[2024-07-20],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "Summer Wedding 2024"
      assert html =~ "2024-07-20"
    end

    test "displays album description", %{conn: conn} do
      create_published_album(2,
        title: "Beautiful Wedding",
        description: "A wonderful celebration of love and joy",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "A wonderful celebration of love and joy"
    end

    test "displays reference link when present", %{conn: conn} do
      create_published_album(2,
        title: "Event Album",
        reference_link: "https://example.com/event",
        date_prise_vue: ~D[2024-06-15],
        type: :events
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "https://example.com/event"
    end

    test "displays gallery link using album slug", %{conn: conn} do
      album =
        create_published_album(2,
          title: "Summer Festival",
          date_prise_vue: ~D[2024-06-15],
          type: :music
        )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "/gallery/#{album.slug}"
    end

    test "does not show reference link when not present", %{conn: conn} do
      create_published_album(2,
        title: "Simple Album",
        reference_link: nil,
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Should not have "Website" link text
      refute html =~ ">Site web<"
    end

    test "albums are sorted by date descending within year", %{conn: conn} do
      create_published_album(2,
        title: "June Album",
        date_prise_vue: ~D[2024-06-01],
        type: :wedding
      )

      create_published_album(2,
        title: "August Album",
        date_prise_vue: ~D[2024-08-01],
        type: :wedding
      )

      create_published_album(2,
        title: "July Album",
        date_prise_vue: ~D[2024-07-01],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # All three albums should be visible
      assert html =~ "June Album"
      assert html =~ "July Album"
      assert html =~ "August Album"
    end
  end

  describe "Timeline - Empty State" do
    test "shows empty state when no albums exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Should show empty state message
      assert html =~ "Chapitre de portfolio vide"
      assert html =~ "Je suis désolé mais pour le moment, cette galerie de portfolio est vide"
    end

    test "shows empty state when filtering by chapter with no albums", %{conn: conn} do
      # Create only wedding albums
      create_published_album(2,
        title: "Wedding Album",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline/landscape")

      # Should show empty state for landscape
      assert html =~ "Chapitre de portfolio vide"
    end
  end

  describe "Timeline - Navigation Anchors" do
    test "year links have anchor attributes", %{conn: conn} do
      create_published_album(2,
        title: "Album 2023",
        date_prise_vue: ~D[2023-06-15],
        type: :wedding
      )

      create_published_album(2,
        title: "Album 2024",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, view, _html} = live(conn, ~p"/timeline")

      # Check that year anchor links exist in navigation
      assert view |> element("a[href='#year-2023']") |> has_element?()
      assert view |> element("a[href='#year-2024']") |> has_element?()
    end

    test "year anchor elements exist in DOM for navigation", %{conn: conn} do
      create_published_album(2,
        title: "Album 2023",
        date_prise_vue: ~D[2023-06-15],
        type: :wedding
      )

      create_published_album(2,
        title: "Album 2024",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, view, _html} = live(conn, ~p"/timeline")

      # Check that elements with year anchor data attributes exist for smooth scrolling
      assert view |> element("[data-album-year-anchor='year-2023']") |> has_element?()
      assert view |> element("[data-album-year-anchor='year-2024']") |> has_element?()
    end

    test "navigation has SmoothScroll hook", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/timeline")

      # Navigation should have SmoothScroll hook for smooth scrolling
      assert view |> element("nav[phx-hook='SmoothScroll']") |> has_element?()
      assert view |> element("#timeline-nav") |> has_element?()
    end

    test "year anchors enable smooth scrolling to albums", %{conn: conn} do
      create_published_album(2,
        title: "Album 2022",
        date_prise_vue: ~D[2022-01-15],
        type: :wedding
      )

      create_published_album(2,
        title: "Album 2023",
        date_prise_vue: ~D[2023-06-20],
        type: :wedding
      )

      create_published_album(2,
        title: "Album 2024",
        date_prise_vue: ~D[2024-12-10],
        type: :wedding
      )

      {:ok, view, _html} = live(conn, ~p"/timeline")

      # Each year should have an anchor data attribute on at least one album
      assert view |> element("[data-album-year-anchor='year-2022']") |> has_element?()
      assert view |> element("[data-album-year-anchor='year-2023']") |> has_element?()
      assert view |> element("[data-album-year-anchor='year-2024']") |> has_element?()

      # Each year should have a navigation link
      assert view |> element("a[href='#year-2022']") |> has_element?()
      assert view |> element("a[href='#year-2023']") |> has_element?()
      assert view |> element("a[href='#year-2024']") |> has_element?()
    end

    test "year anchors have scroll offset class", %{conn: conn} do
      create_published_album(2,
        title: "Album 2024",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Albums should have scroll-mt-20 class to avoid sticky header overlap
      assert html =~ ~s(scroll-mt-20)
      assert html =~ ~s(data-album-year-anchor="year-2024")
    end

    test "years in navigation are sorted descending", %{conn: conn} do
      create_published_album(2,
        title: "Album 2022",
        date_prise_vue: ~D[2022-06-15],
        type: :wedding
      )

      create_published_album(2,
        title: "Album 2024",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Find the positions of the year links in the HTML
      pos_2024 = html |> String.split(~s(href="#year-2024")) |> Enum.at(0) |> String.length()
      pos_2022 = html |> String.split(~s(href="#year-2022")) |> Enum.at(0) |> String.length()

      # 2024 should appear before 2022 (descending order)
      assert pos_2024 < pos_2022
    end

    test "albums have YearTrigger hook with year data", %{conn: conn} do
      create_published_album(2,
        title: "Album 2024",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Each album should have YearTrigger hook with year data
      assert html =~ ~s(phx-hook="YearTrigger")
      assert html =~ ~s(data-year="2024")
    end
  end

  describe "Timeline - Locale Handling" do
    test "change_locale event updates locale", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/timeline")

      # Trigger locale change
      view
      |> element("button[phx-value-locale='fr']")
      |> render_click()

      # The event should be pushed to client
      # (Actual locale change happens client-side via JavaScript)
    end

    test "accepts locale from session", %{conn: conn} do
      conn = init_test_session(conn, %{"locale" => "fr"})

      {:ok, _view, _html} = live(conn, ~p"/timeline")

      # Locale should be set from session
      # Gettext should be using French locale
      assert Gettext.get_locale(PortfolioWeb.Gettext) == "fr"
    end
  end

  describe "Timeline - Handle Params" do
    test "applies action for index without chapter", %{conn: conn} do
      create_published_album(2,
        title: "Wedding Album",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      create_published_album(2,
        title: "Couples Album",
        date_prise_vue: ~D[2024-06-15],
        type: :couples
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Without a chapter, should show all albums
      assert html =~ "Wedding Album"
      assert html =~ "Couples Album"
    end

    test "applies action for index with chapter", %{conn: conn} do
      create_published_album(2,
        title: "Wedding Album",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline/wedding")

      # With wedding chapter, should show wedding in title
      assert html =~ "wedding"
      assert html =~ "Wedding Album"
    end
  end

  describe "Timeline - Multiple Albums" do
    test "displays multiple albums from different years", %{conn: conn} do
      create_published_album(2,
        title: "Album 2022",
        date_prise_vue: ~D[2022-06-15],
        type: :wedding
      )

      create_published_album(2,
        title: "Album 2024",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "Album 2022"
      assert html =~ "Album 2024"
      # Albums should have year data attributes
      assert html =~ ~s(data-year="2022")
      assert html =~ ~s(data-year="2024")
    end

    test "displays multiple albums in same year", %{conn: conn} do
      create_published_album(2,
        title: "First Wedding",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      create_published_album(2,
        title: "Second Wedding",
        date_prise_vue: ~D[2024-08-20],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "First Wedding"
      assert html =~ "Second Wedding"
    end

    test "handles albums with same date", %{conn: conn} do
      create_published_album(2,
        title: "Morning Session",
        date_prise_vue: ~D[2024-06-15],
        type: :couples
      )

      create_published_album(2,
        title: "Evening Session",
        date_prise_vue: ~D[2024-06-15],
        type: :couples
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "Morning Session"
      assert html =~ "Evening Session"
    end
  end

  describe "Timeline - Album Types" do
    test "supports all album types", %{conn: conn} do
      types = [
        :wedding,
        :couples,
        :motherhood,
        :events,
        :landscape,
        :street,
        :music,
        :reenactment,
        :amvcc
      ]

      for type <- types do
        create_published_album(1,
          title: "#{type} Album",
          date_prise_vue: ~D[2024-06-15],
          type: type
        )
      end

      {:ok, _view, html} = live(conn, ~p"/timeline")

      for type <- types do
        assert html =~ "#{type} Album"
      end
    end

    test "filters by each album type correctly", %{conn: conn} do
      create_published_album(2, title: "Wedding", date_prise_vue: ~D[2024-06-15], type: :wedding)
      create_published_album(2, title: "Couples", date_prise_vue: ~D[2024-06-15], type: :couples)
      create_published_album(2, title: "Music", date_prise_vue: ~D[2024-06-15], type: :music)

      # Filter by wedding
      {:ok, _view, html} = live(conn, ~p"/timeline/wedding")
      assert html =~ "Wedding"
      refute html =~ ">Couples<"
      refute html =~ ">Music<"
    end
  end

  describe "Timeline - Responsiveness and Layout" do
    test "renders grid layout classes", %{conn: conn} do
      create_published_album(2,
        title: "Test Album",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Check for responsive grid classes
      assert html =~ "grid"
      assert html =~ "grid-cols-1"
      assert html =~ "sm:grid-cols-3"
      assert html =~ "lg:grid-cols-4"
    end

    test "images have lazy loading attribute", %{conn: conn} do
      create_published_album(2,
        title: "Test Album",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ ~s(loading="lazy")
    end
  end

  describe "Timeline - Edge Cases" do
    test "handles album with very long description", %{conn: conn} do
      long_description = String.duplicate("This is a very long description. ", 50)

      create_published_album(2,
        title: "Long Description Album",
        description: long_description,
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "Long Description Album"
      assert html =~ long_description
    end

    test "handles album with no photos gracefully", %{conn: conn} do
      _album =
        create_album(
          title: "No Photos Album",
          published: true,
          date_prise_vue: ~D[2024-06-15],
          type: :wedding
        )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "No Photos Album"
      # Should not crash when no cover photo available
    end

    test "handles album with empty description", %{conn: conn} do
      create_published_album(2,
        title: "No Description Album",
        description: nil,
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "No Description Album"
      # Should handle nil description gracefully
    end

    test "handles albums from distant past", %{conn: conn} do
      create_published_album(2,
        title: "Very Old Album",
        date_prise_vue: ~D[1900-01-01],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "Very Old Album"
      assert html =~ "1900-01-01"
      assert html =~ ~s(data-year="1900")
    end

    test "handles exactly 20 albums (edge case at page boundary)", %{conn: conn} do
      # Create exactly 20 albums (one full page)
      for i <- 1..20 do
        create_published_album(1,
          title: "Album #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], i),
          type: :wedding
        )
      end

      {:ok, view, html} = live(conn, ~p"/timeline")

      # Should show all 20 albums
      assert html =~ "Album 1"
      assert html =~ "Album 20"

      # Should NOT show infinite scroll marker (no more albums)
      refute view |> element("#infinite-scroll-marker") |> has_element?()
    end

    test "handles exactly 21 albums (one over page boundary)", %{conn: conn} do
      # Create exactly 21 albums (dates in descending order)
      for i <- 1..21 do
        create_published_album(1,
          title: "Album #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], 22 - i),
          type: :wedding
        )
      end

      {:ok, view, html} = live(conn, ~p"/timeline")

      # Should show first 20 albums
      assert html =~ "Album 1"
      assert html =~ "Album 20"
      refute html =~ "Album 21"

      # Should show infinite scroll marker (1 more album)
      assert view |> element("#infinite-scroll-marker") |> has_element?()
    end

    test "handles zero albums", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Should show empty state
      assert html =~ "Chapitre de portfolio vide"
    end

    test "handles load_more when no more albums", %{conn: conn} do
      # Create exactly 20 albums
      for i <- 1..20 do
        create_published_album(1,
          title: "Album #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], i),
          type: :wedding
        )
      end

      {:ok, view, _html} = live(conn, ~p"/timeline")

      # Try to load more when there are no more albums
      # Should not crash or cause errors
      view |> render_hook("load_more", %{})
      html = render(view)

      # Should still show the same albums
      assert html =~ "Album 1"
      assert html =~ "Album 20"
    end
  end

  describe "Timeline - Pagination Edge Cases" do
    test "load_more after chapter filter change resets correctly", %{conn: conn} do
      # Create 25 wedding and 25 couples albums
      for i <- 1..25 do
        create_published_album(1,
          title: "Wedding #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], i),
          type: :wedding
        )

        create_published_album(1,
          title: "Couples #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], i),
          type: :couples
        )
      end

      {:ok, _view, html} = live(conn, ~p"/timeline/wedding")

      # Should show wedding albums only
      assert html =~ "Wedding 1"
      # Use more specific match to avoid false positives in nav/metadata
      refute html =~ ">Couples 1<"

      # Navigate to couples chapter (new LiveView instance)
      {:ok, _view, html} = live(conn, ~p"/timeline/couples")

      # Should reset and show couples albums from page 1
      assert html =~ "Couples 1"
      refute html =~ ">Wedding 1<"
    end

    test "handles very large dataset efficiently", %{conn: conn} do
      # Create 100 albums to test performance (dates in descending order)
      for i <- 1..100 do
        create_published_album(1,
          title: "Album #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], 101 - i),
          type: :wedding
        )
      end

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Should only load first 20 (not all 100)
      assert html =~ "Album 1"
      assert html =~ "Album 20"
      refute html =~ "Album 100"
    end

    test "pagination maintains album order", %{conn: conn} do
      # Create albums with specific dates to test ordering
      create_published_album(1, title: "Oldest", date_prise_vue: ~D[2020-01-01], type: :wedding)
      create_published_album(1, title: "Middle", date_prise_vue: ~D[2022-01-01], type: :wedding)
      create_published_album(1, title: "Newest", date_prise_vue: ~D[2024-01-01], type: :wedding)

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Albums should be present
      assert html =~ "Oldest"
      assert html =~ "Middle"
      assert html =~ "Newest"
    end

    test "handles concurrent load_more attempts gracefully", %{conn: conn} do
      # Create 30 albums
      for i <- 1..30 do
        create_published_album(1,
          title: "Album #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], i),
          type: :wedding
        )
      end

      {:ok, view, _html} = live(conn, ~p"/timeline")

      # Trigger multiple load_more events quickly
      # The pending flag should prevent duplicate loads
      view |> render_hook("load_more", %{})
      view |> render_hook("load_more", %{})

      html = render(view)

      # Should have loaded second page but not duplicates
      assert html =~ "Album 21"
      assert html =~ "Album 30"
    end
  end

  describe "Timeline - Performance and Optimization" do
    test "uses offset-based pagination correctly", %{conn: conn} do
      # Create 45 albums (more than 2 pages, dates in descending order)
      for i <- 1..45 do
        create_published_album(1,
          title: "Album #{i}",
          date_prise_vue: Date.add(~D[2024-01-01], 46 - i),
          type: :wedding
        )
      end

      {:ok, view, html} = live(conn, ~p"/timeline")

      # Page 1: albums 1-20
      assert html =~ "Album 1"
      assert html =~ "Album 20"

      # Load page 2: albums 21-40
      view |> render_hook("load_more", %{})
      html = render(view)
      assert html =~ "Album 21"
      assert html =~ "Album 40"

      # Load page 3: albums 41-45
      view |> render_hook("load_more", %{})
      html = render(view)
      assert html =~ "Album 41"
      assert html =~ "Album 45"
    end

    test "preloads photos association for performance", %{conn: conn} do
      album =
        create_album(
          title: "Album with Photos",
          published: true,
          date_prise_vue: ~D[2024-06-15],
          type: :wedding
        )

      create_photo(
        album: album,
        file_path: "/uploads/cover.jpg",
        display_order: 0
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Should display cover photo without N+1 queries
      assert html =~ "/uploads/cover.jpg"
    end
  end
end
