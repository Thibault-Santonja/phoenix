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
      user = create_user(role: "admin")
      session = create_session(user: user)
      conn = init_test_session(conn, %{session_token: session.token})

      {:ok, _view, html} = live(conn, ~p"/admin/albums")
      assert html =~ "Albums"
    end

    test "displays current user information", %{conn: conn} do
      user = create_user(email: "admin@example.com", name: "Admin User", role: "admin")
      session = create_session(user: user)
      conn = init_test_session(conn, %{session_token: session.token})

      {:ok, _view, html} = live(conn, ~p"/admin/albums")
      assert html =~ "Connecté en tant que"
      assert html =~ "Admin User"
    end

    test "displays user email when name is not set", %{conn: conn} do
      user = create_user(email: "admin@example.com", role: "admin")
      session = create_session(user: user)
      conn = init_test_session(conn, %{session_token: session.token})

      {:ok, _view, html} = live(conn, ~p"/admin/albums")
      assert html =~ "admin@example.com"
    end

    test "provides logout link", %{conn: conn} do
      user = create_user(role: "admin")
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
    user = create_user(role: "admin")
    session = create_session(user: user)

    conn = init_test_session(conn, %{session_token: session.token})

    %{conn: conn, user: user, session: session}
  end
end
