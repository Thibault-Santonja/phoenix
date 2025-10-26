defmodule PortfolioWeb.Admin.AlbumLive.IndexTest do
  use PortfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.{AuthFixtures, PhotographyFixtures}

  alias Portfolio.Photography

  describe "Index - Authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/albums")
      assert path == ~p"/login"
    end

    test "allows access when authenticated", %{conn: conn} do
      user = create_user(role: :admin)
      session = create_session(user: user)
      conn = init_test_session(conn, %{session_token: session.token})

      {:ok, _view, html} = live(conn, ~p"/admin/albums")
      assert html =~ "Albums"
    end

    test "displays current user information", %{conn: conn} do
      user = create_user(email: "admin@example.com", name: "Admin User", role: :admin)
      session = create_session(user: user)
      conn = init_test_session(conn, %{session_token: session.token})

      {:ok, _view, html} = live(conn, ~p"/admin/albums")
      assert html =~ "Connecté en tant que"
      assert html =~ "Admin User"
    end

    test "displays user email when name is not set", %{conn: conn} do
      user = create_user(email: "admin@example.com", role: :admin)
      session = create_session(user: user)
      conn = init_test_session(conn, %{session_token: session.token})

      {:ok, _view, html} = live(conn, ~p"/admin/albums")
      assert html =~ "admin@example.com"
    end

    test "provides logout link", %{conn: conn} do
      user = create_user(role: :admin)
      session = create_session(user: user)
      conn = init_test_session(conn, %{session_token: session.token})

      {:ok, _view, html} = live(conn, ~p"/admin/albums")
      assert html =~ "Déconnexion"
      assert html =~ ~p"/logout"
    end
  end

  describe "Index - Empty State" do
    setup :authenticate_user

    test "displays empty state when no albums exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ "Aucun album"
      assert html =~ "Commencez par créer un nouvel album"
      assert html =~ "Créer un album"
    end

    test "empty state has link to create new album", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Find the "Créer un album" link in empty state
      assert view |> element("a", "Créer un album") |> has_element?()
    end
  end

  describe "Index - Album List" do
    setup :authenticate_user

    test "displays list of albums with basic information", %{conn: conn} do
      _album1 = create_album(title: "Summer Wedding", type: :wedding)
      _album2 = create_album(title: "Maternity Shoot", type: :motherhood)

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ "Summer Wedding"
      assert html =~ "Maternity Shoot"
      assert html =~ "Mariage"
      assert html =~ "Maternité"
    end

    test "displays album location when present", %{conn: conn} do
      create_album(title: "Paris Wedding", location: "Paris, France")
      create_album(title: "Tokyo Streets", location: "Tokyo, Japan")

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ "Paris, France"
      assert html =~ "Tokyo, Japan"
    end

    test "displays album type with correct badge styling", %{conn: conn} do
      create_album(title: "Wedding Album", type: :wedding)

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      # Check that the type badge has correct styling
      assert html =~ "bg-pink-100 text-pink-800"
      assert html =~ "Mariage"
    end

    test "displays all album types correctly", %{conn: conn} do
      types = [
        {:wedding, "Mariage"},
        {:couples, "Couples"},
        {:motherhood, "Maternité"},
        {:events, "Événements"},
        {:landscape, "Paysage"},
        {:street, "Street"},
        {:music, "Musique"},
        {:reenactment, "Reconstitution"},
        {:amvcc, "AMVCC"},
        {:china, "Chine"},
        {:japan, "Japon"},
        {:taiwan, "Taïwan"}
      ]

      for {type, _label} <- types do
        create_album(title: "Album #{type}", type: type)
      end

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      for {_type, label} <- types do
        assert html =~ label
      end
    end

    test "displays formatted date correctly", %{conn: conn} do
      date = ~D[2024-06-15]
      create_album(title: "Summer Wedding", date_prise_vue: date)

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ "15/06/2024"
    end

    test "displays photo count for each album", %{conn: conn} do
      _album1 = create_album_with_photos(3, title: "Wedding with 3 photos")
      _album2 = create_album_with_photos(7, title: "Landscape with 7 photos")

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      # Verify the table contains the correct photo counts
      assert html =~ "Wedding with 3 photos"
      assert html =~ "Landscape with 7 photos"
      # Check for the presence of numbers in table cells (more flexible)
      assert html =~ ~r/<td[^>]*>\s*3\s*<\/td>/
      assert html =~ ~r/<td[^>]*>\s*7\s*<\/td>/
    end

    test "displays zero photos for albums without photos", %{conn: conn} do
      create_album(title: "Empty Album")

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      # Check for 0 in table cell
      assert html =~ ~r/<td[^>]*>\s*0\s*<\/td>/
    end
  end

  describe "Index - Published Status" do
    setup :authenticate_user

    test "displays published toggle for each album", %{conn: conn} do
      create_album(title: "Published Album", published: true)
      create_album(title: "Draft Album", published: false)

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Check that toggle buttons exist
      assert view |> element("button[phx-click='toggle_publish']") |> has_element?()
    end

    test "published toggle shows correct state - published", %{conn: conn} do
      album = create_album(title: "Published Album", published: true)

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Published albums should have bg-indigo-600 (active state)
      button = view |> element("button[phx-value-id='#{album.id}']")
      assert button |> render() =~ "bg-indigo-600"
    end

    test "published toggle shows correct state - unpublished", %{conn: conn} do
      album = create_album(title: "Draft Album", published: false)

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Unpublished albums should have bg-gray-200 (inactive state)
      button = view |> element("button[phx-value-id='#{album.id}']")
      assert button |> render() =~ "bg-gray-200"
    end

    test "toggle_publish changes album from published to unpublished", %{conn: conn} do
      album = create_album(title: "Published Album", published: true)

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Click the toggle button
      view
      |> element("button[phx-value-id='#{album.id}']")
      |> render_click()

      # Verify album was updated
      updated_album = Photography.get_album!(album.id)
      assert updated_album.published == false

      # Verify flash message
      assert render(view) =~ "Statut de publication mis à jour"
    end

    test "toggle_publish changes album from unpublished to published", %{conn: conn} do
      album = create_album(title: "Draft Album", published: false)

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Click the toggle button
      view
      |> element("button[phx-value-id='#{album.id}']")
      |> render_click()

      # Verify album was updated
      updated_album = Photography.get_album!(album.id)
      assert updated_album.published == true

      # Verify flash message
      assert render(view) =~ "Statut de publication mis à jour"
    end

    test "toggle_publish updates the UI without full page reload", %{conn: conn} do
      album = create_album(title: "Album", published: false)

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Initial state - unpublished (gray)
      html_before = render(view)
      assert html_before =~ "bg-gray-200"

      # Toggle to published
      view
      |> element("button[phx-value-id='#{album.id}']")
      |> render_click()

      # New state - published (indigo)
      html_after = render(view)
      assert html_after =~ "bg-indigo-600"
    end
  end

  describe "Index - Actions" do
    setup :authenticate_user

    test "displays edit link for each album", %{conn: conn} do
      album = create_album(title: "Test Album")

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      assert view |> element("a", "Éditer") |> has_element?()
      assert view |> element("a[href='/admin/albums/#{album.id}/edit']") |> has_element?()
    end

    test "displays delete link for each album", %{conn: conn} do
      album = create_album(title: "Test Album")

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      assert view
             |> element("a[phx-click='delete'][phx-value-id='#{album.id}']")
             |> has_element?()
    end

    test "delete link has confirmation prompt", %{conn: conn} do
      album = create_album(title: "Test Album")

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      delete_link = view |> element("a[phx-value-id='#{album.id}']") |> render()
      assert delete_link =~ "data-confirm"
      assert delete_link =~ "Êtes-vous sûr de vouloir supprimer cet album ?"
    end

    test "displays 'Nouvel album' button in header", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      assert view |> element("a", "Nouvel album") |> has_element?()
      assert view |> element("a[href='/admin/albums/new']") |> has_element?()
    end
  end

  describe "Index - Delete Album" do
    setup :authenticate_user

    test "deletes album successfully", %{conn: conn} do
      album = create_album(title: "Album to Delete")

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Verify album is displayed
      assert render(view) =~ "Album to Delete"

      # Delete the album
      view
      |> element("a[phx-click='delete'][phx-value-id='#{album.id}']")
      |> render_click()

      # Verify album is removed from UI
      refute render(view) =~ "Album to Delete"

      # Verify flash message
      assert render(view) =~ "Album supprimé avec succès"

      # Verify album is deleted from database
      assert_raise Ecto.NoResultsError, fn ->
        Photography.get_album!(album.id)
      end
    end

    test "deletes album with photos", %{conn: conn} do
      album = create_album_with_photos(3, title: "Album with Photos")

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Delete the album
      view
      |> element("a[phx-click='delete'][phx-value-id='#{album.id}']")
      |> render_click()

      # Verify success
      assert render(view) =~ "Album supprimé avec succès"

      # Verify album is deleted (cascade should delete photos too)
      assert_raise Ecto.NoResultsError, fn ->
        Photography.get_album!(album.id)
      end
    end

    test "shows empty state after deleting last album", %{conn: conn} do
      album = create_album(title: "Only Album")

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Delete the only album
      view
      |> element("a[phx-click='delete'][phx-value-id='#{album.id}']")
      |> render_click()

      # Verify empty state is shown
      assert render(view) =~ "Aucun album"
      assert render(view) =~ "Commencez par créer un nouvel album"
    end

    test "deleting one album keeps others visible", %{conn: conn} do
      _album1 = create_album(title: "Album to Keep")
      album2 = create_album(title: "Album to Delete")

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Delete album2
      view
      |> element("a[phx-click='delete'][phx-value-id='#{album2.id}']")
      |> render_click()

      # Verify album1 is still visible
      assert render(view) =~ "Album to Keep"
      # Verify album2 is gone
      refute render(view) =~ "Album to Delete"
    end
  end

  describe "Index - Multiple Albums Ordering" do
    setup :authenticate_user

    test "displays albums in order returned by Photography context", %{conn: conn} do
      # Create albums with different dates
      _album1 = create_album(title: "Oldest", date_prise_vue: ~D[2024-01-01])
      _album2 = create_album(title: "Newest", date_prise_vue: ~D[2024-12-31])
      _album3 = create_album(title: "Middle", date_prise_vue: ~D[2024-06-15])

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      # All albums should be visible
      assert html =~ "Oldest"
      assert html =~ "Newest"
      assert html =~ "Middle"

      # The order is determined by Photography.list_albums/1
      # We're just verifying they're all present
      albums = Photography.list_albums()
      assert length(albums) == 3
    end

    test "handles large number of albums", %{conn: conn} do
      # Create 20 albums
      for i <- 1..20 do
        create_album(title: "Album #{i}")
      end

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      # Verify all albums are displayed (no pagination yet)
      assert html =~ "Album 1"
      assert html =~ "Album 10"
      assert html =~ "Album 20"
    end
  end

  describe "Index - Mixed Published/Unpublished Albums" do
    setup :authenticate_user

    test "displays both published and unpublished albums", %{conn: conn} do
      create_album(title: "Published Album", published: true)
      create_album(title: "Draft Album", published: false)

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ "Published Album"
      assert html =~ "Draft Album"
    end

    test "correctly shows toggle state for mixed albums", %{conn: conn} do
      published = create_album(title: "Published", published: true)
      draft = create_album(title: "Draft", published: false)

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Published album toggle
      published_toggle = view |> element("button[phx-value-id='#{published.id}']") |> render()
      assert published_toggle =~ "bg-indigo-600"

      # Draft album toggle
      draft_toggle = view |> element("button[phx-value-id='#{draft.id}']") |> render()
      assert draft_toggle =~ "bg-gray-200"
    end
  end

  describe "Index - Navigation" do
    setup :authenticate_user

    test "edit link navigates to edit page", %{conn: conn} do
      album = create_album(title: "Test Album")

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Click edit link
      {:error, {:live_redirect, %{to: path}}} =
        view
        |> element("a[href='/admin/albums/#{album.id}/edit']")
        |> render_click()

      assert path == ~p"/admin/albums/#{album.id}/edit"
    end

    test "'Nouvel album' button navigates to new album page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Click "Nouvel album" button (the one in header, not in empty state)
      {:error, {:live_redirect, %{to: path}}} =
        view
        |> element("a", "Nouvel album")
        |> render_click()

      assert path == ~p"/admin/albums/new"
    end

    test "has back button to dashboard", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ "Retour au tableau de bord"
      assert html =~ ~s(href="/admin")
    end

    test "back button navigates to dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      assert has_element?(view, "a[href=\"/admin\"]")
    end
  end

  describe "Index - Edge Cases" do
    setup :authenticate_user

    test "handles album with very long title gracefully", %{conn: conn} do
      # Max title length is 200 characters, so create a title at that limit
      long_title = String.duplicate("A", 200)
      create_album(title: long_title)

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ long_title
    end

    test "handles album with special characters in title", %{conn: conn} do
      special_title = "Album & Title <with> \"Special\" 'Characters'"
      create_album(title: special_title)

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      # Phoenix.HTML escapes special characters
      assert html =~ "Album &amp; Title"
    end

    test "handles album with nil location", %{conn: conn} do
      create_album(title: "No Location Album", location: nil)

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ "No Location Album"
      # Location should not cause errors when nil
    end

    test "handles very old dates correctly", %{conn: conn} do
      old_date = ~D[1900-01-01]
      create_album(title: "Old Album", date_prise_vue: old_date)

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ "01/01/1900"
    end

    test "handles dates close to current date correctly", %{conn: conn} do
      # Albums can't have future dates, so test with today's date
      today = Date.utc_today()
      create_album(title: "Today's Album", date_prise_vue: today)

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      # Format today's date as it would appear in the UI (DD/MM/YYYY)
      formatted_date = Calendar.strftime(today, "%d/%m/%Y")
      assert html =~ formatted_date
    end
  end

  describe "Index - Real-time Updates" do
    setup :authenticate_user

    test "album list updates after creating new album from another view", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Initially no albums
      assert render(view) =~ "Aucun album"

      # Create an album directly through context (simulating another user/tab)
      Photography.create_album(%{
        title: "New Album",
        type: :wedding,
        date_prise_vue: Date.utc_today()
      })

      # Note: Without PubSub, we need to manually refresh
      # In a real scenario with PubSub, the LiveView would auto-update
      # For now, we verify that reloading shows the new album
      {:ok, _view2, html} = live(conn, ~p"/admin/albums")
      assert html =~ "New Album"
    end
  end

  describe "Index - Accessibility" do
    setup :authenticate_user

    test "table has proper headers", %{conn: conn} do
      create_album(title: "Test Album")

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ "Titre"
      assert html =~ "Type"
      assert html =~ "Date"
      assert html =~ "Photos"
      assert html =~ "Publié"
      assert html =~ "Actions"
    end

    test "toggle button has sr-only label", %{conn: conn} do
      create_album(title: "Test Album")

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ "Toggle published"
      assert html =~ "sr-only"
    end

    test "actions column has sr-only header", %{conn: conn} do
      create_album(title: "Test Album")

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ ~s(<span class="sr-only">Actions</span>)
    end
  end

  # Test helper to authenticate a user for tests
  defp authenticate_user(%{conn: conn}) do
    user = create_user(role: :admin)
    session = create_session(user: user)

    conn = init_test_session(conn, %{session_token: session.token})

    %{conn: conn, user: user, session: session}
  end

  describe "Index - Filtering" do
    setup [:authenticate_user]

    test "filters albums by published status", %{conn: conn} do
      _published = create_album(title: "Published Album", published: true)
      _draft = create_album(title: "Draft Album", published: false)

      {:ok, _view, html} = live(conn, ~p"/admin/albums?filter=published")

      assert html =~ "Published Album"
      refute html =~ "Draft Album"
    end

    test "filters albums by draft status", %{conn: conn} do
      _published = create_album(title: "Published Album", published: true)
      _draft = create_album(title: "Draft Album", published: false)

      {:ok, _view, html} = live(conn, ~p"/admin/albums?filter=draft")

      refute html =~ "Published Album"
      assert html =~ "Draft Album"
    end

    test "shows all albums when no filter applied", %{conn: conn} do
      _published = create_album(title: "Published Album", published: true)
      _draft = create_album(title: "Draft Album", published: false)

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ "Published Album"
      assert html =~ "Draft Album"
    end

    test "displays filter UI with active filter highlighted", %{conn: conn} do
      create_album(published: true)

      {:ok, _view, html} = live(conn, ~p"/admin/albums?filter=published")

      assert html =~ "Filtrer :"
      # The published filter should be highlighted
      assert html =~ "filter=published"
    end
  end

  describe "Index - Sorting" do
    setup [:authenticate_user]

    test "sorts albums by title ascending", %{conn: conn} do
      _album_c = create_album(title: "Charlie", date_prise_vue: ~D[2024-01-01])
      _album_a = create_album(title: "Alpha", date_prise_vue: ~D[2024-02-01])
      _album_b = create_album(title: "Bravo", date_prise_vue: ~D[2024-03-01])

      {:ok, _view, html} = live(conn, ~p"/admin/albums?sort_by=title&sort_order=asc")

      # Albums should appear in title order: Alpha, Bravo, Charlie
      alpha_pos = :binary.match(html, "Alpha") |> elem(0)
      bravo_pos = :binary.match(html, "Bravo") |> elem(0)
      charlie_pos = :binary.match(html, "Charlie") |> elem(0)

      assert alpha_pos < bravo_pos
      assert bravo_pos < charlie_pos
    end

    test "sorts albums by title descending", %{conn: conn} do
      _album_c = create_album(title: "Charlie", date_prise_vue: ~D[2024-01-01])
      _album_a = create_album(title: "Alpha", date_prise_vue: ~D[2024-02-01])
      _album_b = create_album(title: "Bravo", date_prise_vue: ~D[2024-03-01])

      {:ok, _view, html} = live(conn, ~p"/admin/albums?sort_by=title&sort_order=desc")

      # Albums should appear in reverse title order: Charlie, Bravo, Alpha
      alpha_pos = :binary.match(html, "Alpha") |> elem(0)
      bravo_pos = :binary.match(html, "Bravo") |> elem(0)
      charlie_pos = :binary.match(html, "Charlie") |> elem(0)

      assert charlie_pos < bravo_pos
      assert bravo_pos < alpha_pos
    end

    test "sorts albums by date ascending", %{conn: conn} do
      _album_c = create_album(title: "Newest", date_prise_vue: ~D[2024-03-01])
      _album_a = create_album(title: "Oldest", date_prise_vue: ~D[2024-01-01])
      _album_b = create_album(title: "Middle", date_prise_vue: ~D[2024-02-01])

      {:ok, _view, html} = live(conn, ~p"/admin/albums?sort_by=date&sort_order=asc")

      # Albums should appear in date order: Oldest, Middle, Newest
      oldest_pos = :binary.match(html, "Oldest") |> elem(0)
      middle_pos = :binary.match(html, "Middle") |> elem(0)
      newest_pos = :binary.match(html, "Newest") |> elem(0)

      assert oldest_pos < middle_pos
      assert middle_pos < newest_pos
    end

    test "sorts albums by date descending", %{conn: conn} do
      _album_c = create_album(title: "Newest", date_prise_vue: ~D[2024-03-01])
      _album_a = create_album(title: "Oldest", date_prise_vue: ~D[2024-01-01])
      _album_b = create_album(title: "Middle", date_prise_vue: ~D[2024-02-01])

      {:ok, _view, html} = live(conn, ~p"/admin/albums?sort_by=date&sort_order=desc")

      # Albums should appear in reverse date order: Newest, Middle, Oldest
      oldest_pos = :binary.match(html, "Oldest") |> elem(0)
      middle_pos = :binary.match(html, "Middle") |> elem(0)
      newest_pos = :binary.match(html, "Newest") |> elem(0)

      assert newest_pos < middle_pos
      assert middle_pos < oldest_pos
    end

    test "displays sort indicators on column headers", %{conn: conn} do
      create_album(title: "Test")

      {:ok, _view, html} = live(conn, ~p"/admin/albums?sort_by=title&sort_order=asc")

      # Should show ascending arrow for title column
      assert html =~ "↑"
    end

    test "clicking column header sorts by that column", %{conn: conn} do
      create_album(title: "Album A")
      create_album(title: "Album B")

      {:ok, view, _html} = live(conn, ~p"/admin/albums")

      # Click on title header to sort
      view
      |> element("a", "Titre")
      |> render_click()

      # Should update the view with sort parameters
      assert render(view) =~ "sort_by=title"
      assert render(view) =~ "sort_order"
    end

    test "sorting persists with pagination", %{conn: conn} do
      # Create 40 albums to trigger pagination (30 per page)
      for i <- 1..40 do
        create_album(title: "Album #{String.pad_leading(Integer.to_string(i), 2, "0")}")
      end

      {:ok, _view, html} = live(conn, ~p"/admin/albums?sort_by=title&sort_order=desc&page=1")

      # Should maintain sort parameters in pagination links
      assert html =~ "sort_by=title"
      assert html =~ "sort_order=desc"
    end

    test "sorting works with filters", %{conn: conn} do
      create_album(title: "Zebra", published: true)
      create_album(title: "Alpha", published: true)
      create_album(title: "Middle", published: false)

      {:ok, _view, html} =
        live(conn, ~p"/admin/albums?filter=published&sort_by=title&sort_order=asc")

      # Should show only published albums in sorted order
      assert html =~ "Alpha"
      assert html =~ "Zebra"
      refute html =~ "Middle"

      # Alpha should appear before Zebra
      alpha_pos = :binary.match(html, "Alpha") |> elem(0)
      zebra_pos = :binary.match(html, "Zebra") |> elem(0)
      assert alpha_pos < zebra_pos
    end
  end

  describe "Index - Pagination" do
    setup [:authenticate_user]

    test "displays first page of albums when there are more than 30", %{conn: conn} do
      # Create 40 albums to trigger pagination (30 per page)
      for i <- 1..40 do
        create_album(title: "Album #{i}")
      end

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      # Should show pagination UI
      assert html =~ "Affichage de"
      assert html =~ "sur"
      assert html =~ "albums"
    end

    test "paginates to second page", %{conn: conn} do
      # Create 40 albums
      for i <- 1..40 do
        create_album(title: "Album #{String.pad_leading(Integer.to_string(i), 2, "0")}")
      end

      {:ok, _view, html} = live(conn, ~p"/admin/albums?page=2")

      # Should show page 2 content
      assert html =~ "Affichage de"
      # Page 2 shows albums 31-40 (10 albums)
      assert html =~ "31"
      assert html =~ "40"
    end

    test "pagination UI shows correct page numbers", %{conn: conn} do
      # Create 40 albums to get 2 pages
      for i <- 1..40 do
        create_album(title: "Album #{i}")
      end

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      # Should show page numbers
      assert html =~ "page=2"
    end

    test "pagination works with filters", %{conn: conn} do
      # Create 40 published albums and 5 drafts
      for i <- 1..40 do
        create_album(title: "Published #{i}", published: true)
      end

      for i <- 1..5 do
        create_album(title: "Draft #{i}", published: false)
      end

      {:ok, _view, html} = live(conn, ~p"/admin/albums?filter=published&page=2")

      # Should show page 2 of published albums (31-40)
      assert html =~ "filter=published"
      assert html =~ "Affichage de"
      assert html =~ "31"
      assert html =~ "40"
    end

    test "hides pagination when albums fit on one page", %{conn: conn} do
      # Create only 10 albums (less than 30 per page)
      for i <- 1..10 do
        create_album(title: "Album #{i}")
      end

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      # Should not show pagination
      refute html =~ "Précédent"
      refute html =~ "Suivant"
    end

    test "pagination displays total album count", %{conn: conn} do
      for i <- 1..40 do
        create_album(title: "Album #{i}")
      end

      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ "40"
      assert html =~ "albums"
    end
  end
end
