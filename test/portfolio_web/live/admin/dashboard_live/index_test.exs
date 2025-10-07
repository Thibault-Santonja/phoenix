defmodule PortfolioWeb.Admin.DashboardLive.IndexTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.{AuthFixtures, PhotographyFixtures}

  alias Portfolio.{Auth, Photography}

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

      assert html =~ "Tableau de bord administrateur"
      assert html =~ "Bienvenue, #{user.email}"
      assert html =~ "Statistiques"
    end

    test "shows correct album statistics", %{conn: conn} do
      # Create test albums
      album1 = create_album(title: "Published Album", published: true)
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
      assert html =~ "brouillon"
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
      assert html =~ "Créer un album"
      assert html =~ "Mon profil"
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
      assert html =~ "Email du compte"
      assert html =~ user.email
      assert html =~ "Rôle"
      assert html =~ "Admin"
    end

    test "draft albums link navigates with filter parameter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert view
             |> element("a[href=\"/admin/albums?filter=draft\"]")
             |> render() =~ "brouillon"
    end

    test "published albums link navigates with filter parameter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert view
             |> element("a[href=\"/admin/albums?filter=published\"]")
             |> render() =~ "publié"
    end
  end
end
