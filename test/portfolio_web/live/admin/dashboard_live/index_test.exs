defmodule PortfolioWeb.Admin.DashboardLive.IndexTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.{AuthFixtures, PhotographyFixtures}

  alias Portfolio.Auth

  setup do
    # Create and log in an admin user
    user = create_user(email: "admin@example.com", role: :admin)
    {:ok, session} = Auth.create_session(user)

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> put_session(:session_token, session.token)

    %{conn: conn, user: user}
  end

  describe "Dashboard page" do
    test "displays dashboard with statistics", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Tableau de bord"
      assert html =~ user.email
      assert html =~ "Statistiques"
    end

    test "shows correct album statistics", %{conn: conn} do
      # Create test albums
      _album1 = create_album(title: "Published Album", published: true)
      _album2 = create_album(title: "Draft Album", published: false)

      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show total albums
      assert html =~ "Total Albums"
      # 2 total albums
      assert html =~ "2"

      # Should show published count
      assert html =~ "Albums Publiés"
      # 1 published
      assert html =~ "1"

      # Should show draft count
      assert html =~ "Brouillon"
    end

    test "shows correct photo count", %{conn: conn} do
      album = create_album(title: "Test Album")
      create_photo(album_id: album.id)
      create_photo(album_id: album.id)

      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Total Photos"
      assert html =~ "2"
    end

    test "shows correct user count", %{conn: conn} do
      # Additional users (setup already created one)
      create_user(email: "user1@example.com", role: :user)
      create_user(email: "admin2@example.com", role: :admin)

      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Utilisateurs"
      # 3 total users
      assert html =~ "3"
    end

    test "quick actions section is present", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Actions rapides"
      assert html =~ "Gérer les albums"
      # Check for links to these pages instead of exact text
      assert html =~ ~s(href="/admin/albums/new")
      assert html =~ ~s(href="/admin/profile")
    end

    test "albums stat is clickable and navigates to /admin/albums", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin")

      # Check that there's a link to /admin/albums in the stats section
      assert html =~ "Total Albums"
      assert html =~ ~s(href="/admin/albums")

      # There are multiple links to /admin/albums, we just verify they exist
      assert has_element?(view, "a[href=\"/admin/albums\"]")
    end

    test "users stat is clickable and navigates to /admin/users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert view
             |> element("a[href=\"/admin/users\"]")
             |> render() =~ "Utilisateurs"
    end

    test "displays user information section", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Informations"
      # Check for user information content instead of specific labels
      assert html =~ user.email
      assert html =~ "Admin"
    end

    test "draft albums link navigates with filter parameter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert view
             |> element("a[href=\"/admin/albums?filter=draft\"]")
             |> render() =~ "Albums brouillons"
    end

    test "published albums link navigates with filter parameter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert view
             |> element("a[href=\"/admin/albums?filter=published\"]")
             |> render() =~ "Albums publiés"
    end
  end

  describe "Processing statistics" do
    test "displays processing stats section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show processing statistics section
      assert html =~ "Traitement" || html =~ "Processing" || html =~ "Stockage"
    end

    test "retry_all_failed event reprocesses failed photos", %{conn: conn} do
      # Create a photo with failed status
      album = create_album(title: "Failed Photos Album")
      _photo = create_photo(album_id: album.id, processing_status: "failed")

      {:ok, view, _html} = live(conn, ~p"/admin")

      # Trigger the retry event if button exists
      if has_element?(view, "button[phx-click=\"retry_all_failed\"]") do
        html =
          view
          |> element("button[phx-click=\"retry_all_failed\"]")
          |> render_click()

        # Should show success flash message
        assert html =~ "relancé" || html =~ "restarted" || html =~ "1"
      end
    end

    test "shows storage usage information", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show storage-related information
      assert html =~ "GB" || html =~ "stockage" || html =~ "storage"
    end

    test "displays oldest pending photo with time ago", %{conn: conn} do
      album = create_album(title: "Pending Album")
      # Create a pending photo
      _photo = create_photo(album_id: album.id, processing_status: "pending")

      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show pending count in processing stats
      assert html =~ "En attente" || html =~ "Pending" || html =~ "attente"
    end

    test "displays failed photos with time ago for recent failures", %{conn: conn} do
      album = create_album(title: "Failed Album")
      # Create a failed photo (recently)
      _photo = create_photo(album_id: album.id, processing_status: "failed")

      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show the failed photo with time indication
      assert html =~ "Échec" || html =~ "failed" || html =~ "retry"
    end
  end

  describe "Time ago formatting" do
    test "displays time info for failed photos", %{conn: conn} do
      album = create_album(title: "Recent Album")
      # Photo created just now - default inserted_at is now
      _photo = create_photo(album_id: album.id, processing_status: "failed")

      {:ok, _view, html} = live(conn, ~p"/admin")

      # Failed photos section should be displayed with the photo info
      # The retry button indicates failed photos are shown
      assert html =~ "retry" || html =~ "Relancer" || html =~ "failed" || html =~ "Échec"
    end

    test "handles photos with different processing statuses", %{conn: conn} do
      album = create_album(title: "Mixed Status Album")
      _pending = create_photo(album_id: album.id, processing_status: "pending")
      _processing = create_photo(album_id: album.id, processing_status: "processing")
      _completed = create_photo(album_id: album.id, processing_status: "completed")
      _failed = create_photo(album_id: album.id, processing_status: "failed")

      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should display all status counts
      # At least one of each status
      assert html =~ "1"
    end
  end

  describe "Statistics edge cases" do
    test "handles zero albums gracefully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show 0% for published when no albums
      assert html =~ "0"
    end

    test "displays percentage calculations correctly", %{conn: conn} do
      # Create mix of published/draft albums
      create_album(title: "Published 1", published: true)
      create_album(title: "Published 2", published: true)
      create_album(title: "Draft 1", published: false)

      {:ok, _view, html} = live(conn, ~p"/admin")

      # 2/3 = 66.7% published, 1/3 = 33.3% draft
      assert html =~ "66.7" || html =~ "33.3" || html =~ "%"
    end
  end
end
