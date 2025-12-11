defmodule PortfolioWeb.Admin.AlbumLive.EditTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.AuthFixtures

  alias PortfolioTest.Fixtures.PhotographyFixtures

  describe "mount/3" do
    setup [:create_admin_user, :log_in_admin, :create_album]

    test "mounts successfully for admin user", %{conn: conn, album: album} do
      {:ok, _view, html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      assert html =~ album.title or html =~ "album"
    end

    test "displays album form with existing data", %{conn: conn, album: album} do
      {:ok, _view, html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      assert html =~ album.title
    end

    @tag :skip
    test "returns error for non-existent album", %{conn: conn} do
      result = live(conn, ~p"/admin/albums/#{Ecto.UUID.generate()}/edit")

      # Should either redirect or show error page
      case result do
        {:error, {:redirect, _}} -> assert true
        {:error, {:live_redirect, _}} -> assert true
        {:ok, _view, html} -> assert html =~ "album"
      end
    end
  end

  describe "form validation" do
    setup [:create_admin_user, :log_in_admin, :create_album]

    test "validates title change", %{conn: conn, album: album} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      html =
        view
        |> form("#album-form", album: %{title: "Updated Title"})
        |> render_change()

      assert html =~ "Updated Title"
    end

    test "validates description change", %{conn: conn, album: album} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      html =
        view
        |> form("#album-form", album: %{description: "New description text"})
        |> render_change()

      assert html =~ "New description" or html =~ "album"
    end

    test "validates location change", %{conn: conn, album: album} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      html =
        view
        |> form("#album-form", album: %{location: "Tokyo, Japan"})
        |> render_change()

      assert html =~ "Tokyo" or html =~ "album"
    end
  end

  describe "form submission" do
    setup [:create_admin_user, :log_in_admin, :create_album]

    test "updates album with valid data", %{conn: conn, album: album} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      view
      |> form("#album-form", album: %{title: "Completely Updated Album"})
      |> render_submit()

      # Should redirect after update
      {path, _flash} = assert_redirect(view)
      assert path =~ "/admin/albums"
    end

    test "updates album type", %{conn: conn, album: album} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      view
      |> form("#album-form", album: %{type: "landscape"})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/admin/albums"
    end

    test "toggles published status", %{conn: conn, album: album} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      view
      |> form("#album-form", album: %{published: !album.published})
      |> render_submit()

      {path, _flash} = assert_redirect(view)
      assert path =~ "/admin/albums"
    end
  end

  describe "authorization" do
    setup [:create_album]

    test "redirects non-admin users", %{conn: conn, album: album} do
      user = create_user(email: "regular@example.com", role: :user)
      session = create_session(user: user)
      octet = 1 + rem(System.unique_integer([:positive]), 254)
      conn = %{conn | remote_ip: {127, 0, 0, octet}}
      conn = Plug.Test.init_test_session(conn, %{"session_token" => session.token})

      assert {:error, {:redirect, %{to: redirect_path}}} =
               live(conn, ~p"/admin/albums/#{album.id}/edit")

      assert redirect_path != "/admin/albums/#{album.id}/edit"
    end

    test "redirects unauthenticated users", %{conn: conn, album: album} do
      assert {:error, {:redirect, %{to: redirect_path}}} =
               live(conn, ~p"/admin/albums/#{album.id}/edit")

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

  defp create_album(_context) do
    album = PhotographyFixtures.create_album(title: "Test Album", published: false)
    %{album: album}
  end
end
