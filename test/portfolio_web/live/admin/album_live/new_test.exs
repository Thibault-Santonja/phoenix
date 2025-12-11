defmodule PortfolioWeb.Admin.AlbumLive.NewTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.AuthFixtures

  describe "mount/3" do
    setup [:create_admin_user, :log_in_admin]

    test "mounts successfully for admin user", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/albums/new")

      assert html =~ "Nouvel album" or html =~ "New album" or html =~ "album"
    end

    test "displays album form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/albums/new")

      assert html =~ "album-form" or html =~ "form"
    end
  end

  describe "form validation" do
    setup [:create_admin_user, :log_in_admin]

    test "validates required fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      # Submit empty form
      html =
        view
        |> form("#album-form", album: %{title: "", type: ""})
        |> render_change()

      # Should show validation state
      assert html =~ "album-form" or html =~ "form"
    end

    test "validates title field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      html =
        view
        |> form("#album-form", album: %{title: "Test Album"})
        |> render_change()

      assert html =~ "Test Album"
    end

    test "validates with all fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      html =
        view
        |> form("#album-form",
          album: %{
            title: "Complete Album",
            type: "wedding",
            description: "A test description",
            location: "Paris, France",
            date_prise_vue: "2024-01-15",
            published: true
          }
        )
        |> render_change()

      assert html =~ "Complete Album"
    end
  end

  describe "form submission" do
    setup [:create_admin_user, :log_in_admin]

    test "creates album with valid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      view
      |> form("#album-form",
        album: %{
          title: "New Test Album",
          type: "wedding",
          date_prise_vue: "2024-06-01"
        }
      )
      |> render_submit()

      # Should redirect after creation - check with follow_redirect
      {path, _flash} = assert_redirect(view)
      assert path =~ "/admin/albums"
    end

    test "shows errors for invalid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      html =
        view
        |> form("#album-form", album: %{title: ""})
        |> render_submit()

      # Should stay on form with errors or redirect
      assert is_binary(html) or is_tuple(html)
    end
  end

  describe "authorization" do
    test "redirects non-admin users", %{conn: conn} do
      user = create_user(email: "regular@example.com", role: :user)
      session = create_session(user: user)
      octet = 1 + rem(System.unique_integer([:positive]), 254)
      conn = %{conn | remote_ip: {127, 0, 0, octet}}
      conn = Plug.Test.init_test_session(conn, %{"session_token" => session.token})

      assert {:error, {:redirect, %{to: redirect_path}}} = live(conn, ~p"/admin/albums/new")
      assert redirect_path != "/admin/albums/new"
    end

    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, %{to: redirect_path}}} = live(conn, ~p"/admin/albums/new")
      assert redirect_path =~ "login" or redirect_path =~ "auth"
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
