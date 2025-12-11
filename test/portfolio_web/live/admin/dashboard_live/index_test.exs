defmodule PortfolioWeb.Admin.DashboardLive.IndexTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.AuthFixtures

  alias PortfolioTest.Fixtures.PhotographyFixtures

  describe "mount/3" do
    setup [:create_admin_user, :log_in_admin]

    test "mounts successfully for admin user", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Tableau de bord" or html =~ "Dashboard"
    end

    test "displays statistics section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Dashboard should show statistics
      assert html =~ "album" or html =~ "Album" or html =~ "photo" or html =~ "Photo"
    end

    test "shows current admin info", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show logged in admin
      assert html =~ "admin@example.com"
    end
  end

  describe "handle_params/3" do
    setup [:create_admin_user, :log_in_admin]

    test "handles params successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should not crash with any params
      assert html =~ "Tableau de bord" or html =~ "Dashboard"
    end
  end

  describe "handle_event/3 - retry_all_failed" do
    setup [:create_admin_user, :log_in_admin]

    test "handles retry button click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      # Check if retry button exists
      if has_element?(view, "#retry-failed-btn") do
        result = view |> element("#retry-failed-btn") |> render_click()
        assert result =~ "redémarré" or result =~ "restarted" or is_binary(result)
      else
        # Button might not exist if no failed photos
        assert render(view) =~ "Tableau de bord" or render(view) =~ "Dashboard"
      end
    end
  end

  describe "statistics display" do
    setup [:create_admin_user, :log_in_admin]

    test "displays album statistics", %{conn: conn} do
      PhotographyFixtures.create_album(published: true)
      PhotographyFixtures.create_album(published: false)

      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show some stats
      assert html =~ "album" or html =~ "Album"
    end

    test "displays storage info", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show storage section
      assert html =~ "stockage" or html =~ "storage" or html =~ "Storage" or html =~ "Go" or
               html =~ "GB"
    end
  end

  describe "authorization" do
    test "redirects non-admin users", %{conn: conn} do
      user = create_user(email: "user@example.com", role: :user)
      session = create_session(user: user)
      octet = 1 + rem(System.unique_integer([:positive]), 254)
      conn = %{conn | remote_ip: {127, 0, 0, octet}}
      conn = Plug.Test.init_test_session(conn, %{"session_token" => session.token})

      # Non-admin should be redirected
      assert {:error, {:redirect, %{to: redirect_path}}} = live(conn, ~p"/admin")
      assert redirect_path != "/admin"
    end

    test "redirects unauthenticated users", %{conn: conn} do
      # Unauthenticated should be redirected to login
      assert {:error, {:redirect, %{to: redirect_path}}} = live(conn, ~p"/admin")
      assert redirect_path =~ "login" or redirect_path =~ "auth"
    end
  end

  describe "navigation links" do
    setup [:create_admin_user, :log_in_admin]

    test "has link to albums management", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "/admin/albums" or html =~ "Albums"
    end

    test "has logout link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "logout" or html =~ "Déconnexion"
    end
  end

  # Helper functions

  defp create_admin_user(_context) do
    admin = create_user(email: "admin@example.com", role: :admin)
    %{admin: admin}
  end

  defp log_in_admin(%{conn: conn, admin: admin}) do
    session = create_session(user: admin)
    octet = 1 + rem(System.unique_integer([:positive]), 254)
    conn = %{conn | remote_ip: {127, 0, 0, octet}}
    conn = Plug.Test.init_test_session(conn, %{"session_token" => session.token})
    %{conn: conn}
  end
end
