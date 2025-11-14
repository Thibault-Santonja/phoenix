defmodule PortfolioWeb.Admin.ProfileLive.EditTest do
  use PortfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Auth
  alias Portfolio.Auth.User
  alias Portfolio.Repo

  describe "mount" do
    setup :register_and_log_in_user

    test "displays user profile information", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, ~p"/admin/profile")

      assert html =~ "Mon profil"
      assert html =~ user.email
      assert html =~ String.capitalize(to_string(user.role))
      assert has_element?(view, "form")
      assert has_element?(view, "input[name=\"user[name]\"]")
    end

    test "shows current session in sessions list", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      assert has_element?(view, "div", "Session actuelle")
      assert render(view) =~ Calendar.strftime(session.last_activity_at, "%d/%m/%Y")
    end
  end

  describe "save event" do
    setup :register_and_log_in_user

    test "updates user name successfully", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      html =
        view
        |> form("form", %{user: %{name: "Updated Name"}})
        |> render_submit()

      assert html =~ "Profil mis à jour avec succès"

      # Vérifier que le nom a été mis à jour en base
      updated_user = Repo.get!(User, user.id)
      assert updated_user.name == "Updated Name"
    end

    test "shows validation error for invalid name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      html =
        view
        |> form("form", %{user: %{name: "A"}})
        |> render_submit()

      # Le nom doit faire au moins 2 caractères
      assert html =~ "should be at least 2 character" or html =~ "au moins 2"
    end

    test "cannot modify email through profile form", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      # L'email doit être désactivé (disabled)
      assert has_element?(view, "input[type=\"email\"][disabled]")
      assert has_element?(view, "input[value=\"#{user.email}\"][disabled]")

      # Soumettre uniquement le nom (l'email désactivé ne sera pas soumis)
      view
      |> form("form", %{user: %{name: "Test Name"}})
      |> render_submit()

      # Vérifier que l'email n'a pas changé
      updated_user = Repo.get!(User, user.id)
      assert updated_user.email == user.email
      assert updated_user.name == "Test Name"
    end
  end

  describe "revoke_session event" do
    setup :register_and_log_in_user

    test "revokes a specific session", %{conn: conn, user: user} do
      # Créer une deuxième session
      {:ok, other_session} = Auth.create_session(user)

      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      # Vérifier que les deux sessions sont affichées
      sessions_html = render(view)
      assert sessions_html =~ "Session actuelle"
      # Au moins 2 sessions

      # Révoquer la deuxième session
      html =
        view
        |> element(~s(button[phx-click="revoke_session"][phx-value-id="#{other_session.id}"]))
        |> render_click()

      assert html =~ "Session révoquée avec succès"

      # Vérifier que la session a été supprimée de la base
      assert Auth.get_session_by_token(other_session.token) == nil
    end

    test "cannot revoke current session", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      # Le bouton de révocation ne devrait pas exister pour la session actuelle
      refute has_element?(
               view,
               "button[phx-click=\"revoke_session\"][phx-value-id=\"#{session.id}\"]"
             )
    end
  end

  describe "revoke_all_sessions event" do
    setup :register_and_log_in_user

    test "revokes all other sessions but keeps current", %{
      conn: conn,
      user: user,
      session: current_session
    } do
      # Créer 2 autres sessions
      {:ok, session1} = Auth.create_session(user)
      {:ok, session2} = Auth.create_session(user)

      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      # Révoquer toutes les autres sessions
      html =
        view
        |> element("button[phx-click=\"revoke_all_sessions\"]")
        |> render_click()

      assert html =~ "2 session(s) révoquée(s)"

      # Vérifier que les autres sessions ont été supprimées
      assert Auth.get_session_by_token(session1.token) == nil
      assert Auth.get_session_by_token(session2.token) == nil

      # Vérifier que la session actuelle existe toujours
      assert Auth.get_session_by_token(current_session.token) != nil
    end

    test "does not show button when only one session exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      # Le bouton ne devrait pas être visible s'il n'y a qu'une session
      refute has_element?(view, "button[phx-click=\"revoke_all_sessions\"]")
    end

    test "shows button when multiple sessions exist", %{conn: conn, user: user} do
      # Créer une deuxième session
      {:ok, _other_session} = Auth.create_session(user)

      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      # Le bouton devrait être visible maintenant
      assert has_element?(view, "button[phx-click=\"revoke_all_sessions\"]")
    end
  end

  describe "navigation" do
    setup :register_and_log_in_user

    test "has back button to dashboard", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/profile")

      assert html =~ "Retour au tableau de bord"
      assert html =~ ~s(href="/admin")
    end

    test "back button navigates to dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/profile")

      assert has_element?(view, "a[href=\"/admin\"]")
    end
  end
end
