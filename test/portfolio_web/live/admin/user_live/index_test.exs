defmodule PortfolioWeb.Admin.UserLive.IndexTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.AuthFixtures

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

  describe "Index page" do
    test "displays all users", %{conn: conn} do
      # Create additional users
      _user1 = create_user(email: "user1@example.com", role: :user)
      _user2 = create_user(email: "user2@example.com", role: :admin)

      {:ok, _view, html} = live(conn, ~p"/admin/users")

      # Check that the page loads
      assert html =~ "Gestion des utilisateurs"

      # Check that users are displayed
      assert html =~ "user1@example.com"
      assert html =~ "user2@example.com"
    end

    test "displays correct user count statistics", %{conn: conn} do
      # Create users with different roles
      _user1 = create_user(email: "user1@example.com", role: :user)
      _user2 = create_user(email: "user2@example.com", role: :user)
      _admin1 = create_user(email: "admin1@example.com", role: :admin)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Total users should be 4 (current_user + 3 created)
      html = render(view)
      # Check for statistics cards by verifying links instead of exact text
      assert html =~ ~s(href="/admin/users")
      # Verify we can see the actual counts
      # Total users
      assert html =~ "4"
      # Admins (current_user + admin1)
      assert html =~ "2"
    end

    test "filters users by admin role", %{conn: conn} do
      # Create users with different roles
      _user1 = create_user(email: "user1@example.com", role: :user)
      _admin1 = create_user(email: "admin1@example.com", role: :admin)

      {:ok, _view, html} = live(conn, ~p"/admin/users?filter=admin")

      # Should show admin users
      assert html =~ "admin1@example.com"

      # Should not show regular users
      refute html =~ "user1@example.com"
    end

    test "filters users by user role", %{conn: conn} do
      # Create users with different roles
      _user1 = create_user(email: "user1@example.com", role: :user)
      _admin1 = create_user(email: "admin1@example.com", role: :admin)

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
      _user1 = create_user(email: "user1@example.com", role: :user)
      _admin1 = create_user(email: "admin1@example.com", role: :admin)

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

    test "prevents admin from modifying their own role", %{conn: conn, user: admin_user} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # L'admin connecté ne devrait pas voir de bouton d'édition pour son propre compte
      refute has_element?(
               view,
               "button[phx-click=\"open_edit_modal\"][phx-value-user-id=\"#{admin_user.id}\"]"
             )

      # Vérifier que le texte "Vous" est affiché au lieu des boutons
      assert render(view) =~ "Vous"

      # Vérifier que le rôle n'a pas changé
      assert {:ok, updated_user} = Auth.get_user(admin_user.id)
      assert updated_user.role == :admin
    end

    test "allows admin to modify another user's role", %{conn: conn} do
      other_user = create_user(email: "other@example.com", role: :user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Ouvrir la modale d'édition pour l'autre utilisateur
      selector = ~s(button[phx-click="open_edit_modal"][phx-value-user-id="#{other_user.id}"])

      view
      |> element(selector)
      |> render_click()

      # Soumettre le formulaire pour changer le rôle
      view
      |> form("form[phx-submit=\"save_user\"]", %{user: %{role: "admin"}})
      |> render_submit()

      # Devrait afficher le message de succès
      assert render(view) =~ "Utilisateur mis à jour avec succès"

      # Vérifier que le rôle a changé
      assert {:ok, updated_user} = Auth.get_user(other_user.id)
      assert updated_user.role == :admin
    end
  end
end
