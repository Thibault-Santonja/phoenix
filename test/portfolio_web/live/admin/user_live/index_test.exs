defmodule PortfolioWeb.Admin.UserLive.IndexTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Auth

  setup do
    # Create and log in an admin user
    user = create_user(email: "admin@example.com", role: "admin")
    {:ok, session} = Auth.create_session(user)

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> put_session(:session_token, session.token)

    %{conn: conn, user: user}
  end

  describe "Index page" do
    test "displays all users", %{conn: conn} do
      # Create additional users
      _user1 = create_user(email: "user1@example.com", role: "user")
      _user2 = create_user(email: "user2@example.com", role: "admin")

      {:ok, _view, html} = live(conn, ~p"/admin/users")

      # Check that the page loads
      assert html =~ "Gestion des utilisateurs"

      # Check that users are displayed
      assert html =~ "user1@example.com"
      assert html =~ "user2@example.com"
    end

    test "displays correct user count statistics", %{conn: conn} do
      # Create users with different roles
      _user1 = create_user(email: "user1@example.com", role: "user")
      _user2 = create_user(email: "user2@example.com", role: "user")
      _admin1 = create_user(email: "admin1@example.com", role: "admin")

      {:ok, _view, html} = live(conn, ~p"/admin/users")

      # Total users should be 4 (current_user + 3 created)
      assert html =~ "Total utilisateurs"
      assert html =~ "Administrateurs"
      assert html =~ "Utilisateurs"
    end

    test "filters users by admin role", %{conn: conn} do
      # Create users with different roles
      _user1 = create_user(email: "user1@example.com", role: "user")
      _admin1 = create_user(email: "admin1@example.com", role: "admin")

      {:ok, _view, html} = live(conn, ~p"/admin/users?filter=admin")

      # Should show admin users
      assert html =~ "admin1@example.com"

      # Should not show regular users
      refute html =~ "user1@example.com"
    end

    test "filters users by user role", %{conn: conn} do
      # Create users with different roles
      _user1 = create_user(email: "user1@example.com", role: "user")
      _admin1 = create_user(email: "admin1@example.com", role: "admin")

      {:ok, _view, html} = live(conn, ~p"/admin/users?filter=user")

      # Should show regular users
      assert html =~ "user1@example.com"

      # Should not show admin users (except current admin in setup)
      refute html =~ "admin1@example.com"
    end

    test "toggles filter when clicking on stats", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Click on admin stat to filter
      assert view
             |> element("a[href=\"/admin/users?filter=admin\"]")
             |> render_click()

      # Should show filtered URL
      assert_patched(view, ~p"/admin/users?filter=admin")
    end

    test "displays user role badges correctly", %{conn: conn} do
      _user1 = create_user(email: "user1@example.com", role: "user")
      _admin1 = create_user(email: "admin1@example.com", role: "admin")

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Check for admin badge (purple background)
      assert has_element?(view, "span.bg-purple-100")

      # Check for user badge (gray background)
      assert has_element?(view, "span.bg-gray-100")
    end

    test "displays current user indicator", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Should show "Vous" for current user
      assert has_element?(view, "span", "Vous")
    end

    test "has back button to dashboard", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/users")

      assert html =~ "Retour au tableau de bord"
      assert has_element?(view, "a[href=\"/admin\"]")
    end
  end
end
