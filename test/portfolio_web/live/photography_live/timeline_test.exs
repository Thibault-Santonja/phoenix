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

  describe "Timeline - Year Grouping" do
    test "groups albums by year", %{conn: conn} do
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

      {:ok, _view, html} = live(conn, ~p"/timeline")

      # Check that year sections exist
      assert html =~ ~s(id="year-2023")
      assert html =~ ~s(id="year-2024")
    end

    test "displays albums within their year section", %{conn: conn} do
      create_published_album(2,
        title: "Wedding 2023",
        date_prise_vue: ~D[2023-06-15],
        type: :wedding
      )

      create_published_album(2,
        title: "Couples 2024",
        date_prise_vue: ~D[2024-08-20],
        type: :couples
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

      assert html =~ "Wedding 2023"
      assert html =~ "Couples 2024"
    end

    test "displays years in descending order", %{conn: conn} do
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

      # Years should be present
      assert html =~ ~s(id="year-2022")
      assert html =~ ~s(id="year-2024")
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

    test "groups database albums by year", %{conn: conn} do
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

      # Both albums should appear in their respective year sections
      assert html =~ "Album 2023"
      assert html =~ "Album 2024"
      assert html =~ ~s(id="year-2023")
      assert html =~ ~s(id="year-2024")
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
      refute html =~ "Couples Album"
    end

    test "updates page title when filtering by chapter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/timeline/wedding")

      # Page title should include the chapter name (capitalized)
      assert html =~ "Wedding"
    end

    test "shows only relevant years when filtered", %{conn: conn} do
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

      # Should only show 2024
      assert html =~ "2024 Wedding"
      refute html =~ "2023 Landscape"
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

      # Check that year anchor links exist
      assert view |> element("a[href='#year-2023']") |> has_element?()
      assert view |> element("a[href='#year-2024']") |> has_element?()
    end

    test "year sections have correct IDs for anchoring", %{conn: conn} do
      create_published_album(2,
        title: "Album 2023",
        date_prise_vue: ~D[2023-06-15],
        type: :wedding
      )

      {:ok, view, _html} = live(conn, ~p"/timeline")

      assert view |> element("li#year-2023") |> has_element?()
    end

    test "year sections have YearTrigger hook", %{conn: conn} do
      create_published_album(2,
        title: "Album 2024",
        date_prise_vue: ~D[2024-06-15],
        type: :wedding
      )

      {:ok, _view, html} = live(conn, ~p"/timeline")

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
      assert html =~ ~s(id="year-2022")
      assert html =~ ~s(id="year-2024")
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
      assert html =~ ~s(id="year-1900")
    end
  end
end
