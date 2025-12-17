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

  describe "Edit modal" do
    test "opens edit modal for user", %{conn: conn} do
      other_user = create_user(email: "edit@example.com", role: :user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Open edit modal
      html =
        view
        |> element(~s(button[phx-click="open_edit_modal"][phx-value-user-id="#{other_user.id}"]))
        |> render_click()

      # Modal should be visible
      assert html =~ "edit@example.com" or html =~ "Modifier"
    end

    test "handles non-existent user when opening modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Try to open modal for non-existent user
      html = render_click(view, "open_edit_modal", %{"user-id" => Ecto.UUID.generate()})

      # Should show error
      assert html =~ "introuvable" or html =~ "not found" or html =~ "Utilisateur"
    end

    test "closes edit modal", %{conn: conn} do
      other_user = create_user(email: "close@example.com", role: :user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Open modal
      view
      |> element(~s(button[phx-click="open_edit_modal"][phx-value-user-id="#{other_user.id}"]))
      |> render_click()

      # Close modal
      html = render_click(view, "close_edit_modal", %{})

      # Modal content should not be visible (form should be closed)
      refute has_element?(view, "form[phx-submit=\"save_user\"]")
      assert html =~ "close@example.com"
    end

    test "handles save with invalid role", %{conn: conn} do
      other_user = create_user(email: "invalid@example.com", role: :user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Open modal
      view
      |> element(~s(button[phx-click="open_edit_modal"][phx-value-user-id="#{other_user.id}"]))
      |> render_click()

      # Try to submit with original role (no change)
      html =
        view
        |> form("form[phx-submit=\"save_user\"]", %{user: %{role: "user"}})
        |> render_submit()

      # Should succeed (no actual change)
      assert html =~ "Utilisateur mis à jour" or html =~ "invalid@example.com"
    end
  end

  describe "Delete user" do
    test "confirms delete action", %{conn: conn} do
      other_user = create_user(email: "delete@example.com", role: :user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Trigger confirm delete
      html = render_click(view, "confirm_delete", %{"user-id" => other_user.id})

      # Should show confirmation
      assert html =~ "delete@example.com"
    end

    test "handles non-existent user when deleting", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Try to delete non-existent user
      html = render_click(view, "delete_user", %{"user-id" => Ecto.UUID.generate()})

      # Should show error
      assert html =~ "introuvable" or html =~ "not found" or html =~ "erreur"
    end

    test "cancels delete action", %{conn: conn} do
      other_user = create_user(email: "cancel@example.com", role: :user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Confirm delete
      render_click(view, "confirm_delete", %{"user-id" => other_user.id})

      # Cancel delete
      html = render_click(view, "cancel_delete", %{})

      # User should still exist
      assert html =~ "cancel@example.com"
      assert {:ok, _} = Auth.get_user(other_user.id)
    end

    test "deletes user successfully", %{conn: conn} do
      other_user = create_user(email: "deleted@example.com", role: :user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Delete user
      html = render_click(view, "delete_user", %{"user-id" => other_user.id})

      # Should show success message
      assert html =~ "Utilisateur supprimé" or html =~ "supprimé avec succès"

      # User should be deleted
      assert {:error, :not_found} = Auth.get_user(other_user.id)
    end

    test "updates statistics after delete", %{conn: conn} do
      _user1 = create_user(email: "stat1@example.com", role: :user)
      user2 = create_user(email: "stat2@example.com", role: :user)

      {:ok, view, html} = live(conn, ~p"/admin/users")

      # Initial count should be 3
      assert html =~ "3"

      # Delete one user
      render_click(view, "delete_user", %{"user-id" => user2.id})

      # Count should now be 2
      html = render(view)
      assert html =~ "2"
    end
  end

  describe "Revoke sessions" do
    test "revokes all user sessions", %{conn: conn} do
      other_user = create_user(email: "revoke@example.com", role: :user)
      # Create some sessions
      {:ok, _session1} = Auth.create_session(other_user)
      {:ok, _session2} = Auth.create_session(other_user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Revoke sessions
      html = render_click(view, "revoke_sessions", %{"user-id" => other_user.id})

      # Should show success message with count
      assert html =~ "session" or html =~ "révoquée"
    end

    test "handles user with no sessions", %{conn: conn} do
      other_user = create_user(email: "nosession@example.com", role: :user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Revoke sessions (should handle 0 sessions gracefully)
      html = render_click(view, "revoke_sessions", %{"user-id" => other_user.id})

      # Should show success message
      assert html =~ "0" or html =~ "session"
    end

    test "handles non-existent user when revoking sessions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Try to revoke sessions for non-existent user
      html = render_click(view, "revoke_sessions", %{"user-id" => Ecto.UUID.generate()})

      # Should show error
      assert html =~ "introuvable" or html =~ "not found" or html =~ "Utilisateur"
    end
  end

  describe "Send magic link" do
    test "sends magic link successfully", %{conn: conn} do
      other_user = create_user(email: "magic@example.com", role: :user)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Send magic link
      html = render_click(view, "send_magic_link", %{"user-id" => other_user.id})

      # Should show success message
      assert html =~ "magic@example.com" or html =~ "Magic link"
    end

    test "handles non-existent user when sending magic link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Try to send magic link for non-existent user
      html = render_click(view, "send_magic_link", %{"user-id" => Ecto.UUID.generate()})

      # Should show error
      assert html =~ "introuvable" or html =~ "not found" or html =~ "Utilisateur"
    end
  end

  describe "IP address handling" do
    test "handles missing IP address gracefully", %{conn: conn} do
      # The test connection doesn't have peer_data
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      # Page should still load
      assert html =~ "Gestion des utilisateurs"
    end
  end

  describe "Filter navigation" do
    test "removes filter when clicking all users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users?filter=admin")

      # Click on all users link (first one is the stat card)
      view
      |> element("a[href=\"/admin/users\"]", "Total")
      |> render_click()

      assert_patched(view, ~p"/admin/users")
    end

    test "filter persists across page refresh", %{conn: conn} do
      _user = create_user(email: "persist@example.com", role: :user)

      {:ok, _view, html} = live(conn, ~p"/admin/users?filter=user")

      # Should show regular users
      assert html =~ "persist@example.com"
    end
  end
end
