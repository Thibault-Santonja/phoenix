defmodule PortfolioWeb.Admin.IPWhitelistLive.IndexTest do
  use PortfolioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Auth
  alias Portfolio.Auth.IPWhitelistService

  setup do
    # Initialize ETS cache for IP whitelist tests
    IPWhitelistService.init_cache()

    admin = create_user(email: "admin@example.com", role: :admin)
    {:ok, session} = Auth.create_session(admin)

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> put_session(:session_token, session.token)

    %{conn: conn, admin: admin}
  end

  describe "Index" do
    test "displays the list of whitelisted IPs", %{conn: conn, admin: admin} do
      {:ok, _} =
        IPWhitelistService.add_to_whitelist(
          %{ip_address: "192.168.1.100", description: "Office"},
          admin.id
        )

      {:ok, _} =
        IPWhitelistService.add_to_whitelist(
          %{ip_address: "10.0.0.1", description: "VPN"},
          admin.id
        )

      {:ok, _view, html} = live(conn, ~p"/admin/ip-whitelist")

      assert html =~ "IP Whitelist"
      assert html =~ "192.168.1.100"
      assert html =~ "Office"
      assert html =~ "10.0.0.1"
      assert html =~ "VPN"
    end

    test "displays a message if no whitelisted IPs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/ip-whitelist")

      assert html =~ "IP Whitelist"
      assert html =~ "No whitelisted IPs"
    end

    test "allows adding a new IP", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      # Click the "Add IP" link (live patch)
      html = view |> element("a", "Add IP") |> render_click()

      # Modal should be displayed with form
      assert html =~ "ip-form"

      # Fill and submit the form
      view
      |> form("#ip-form", ip_whitelist: %{ip_address: "192.168.1.100", description: "Test"})
      |> render_submit()

      # Verify the IP appears
      assert render(view) =~ "192.168.1.100"
      assert render(view) =~ "Test"
    end

    test "displays an error if IP is invalid", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      # Navigate to the form (live patch)
      view |> element("a", "Add IP") |> render_click()

      # Submit with an invalid IP
      assert view
             |> form("#ip-form", ip_whitelist: %{ip_address: "invalid_ip"})
             |> render_submit() =~ "has invalid format"
    end

    test "prevents duplicates", %{conn: conn, admin: admin} do
      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: "192.168.1.100"}, admin.id)

      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      # Navigate to the form (live patch)
      view |> element("a", "Add IP") |> render_click()

      # Attempt to add the same IP
      assert view
             |> form("#ip-form", ip_whitelist: %{ip_address: "192.168.1.100"})
             |> render_submit() =~ "has already been taken"
    end

    test "allows deleting an IP", %{conn: conn, admin: admin} do
      {:ok, _} =
        IPWhitelistService.add_to_whitelist(
          %{ip_address: "192.168.1.100", description: "Test"},
          admin.id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      # Verify the IP is present
      assert render(view) =~ "192.168.1.100"

      # Delete the IP
      view
      |> element("button[phx-click=\"delete\"]")
      |> render_click()

      # Verify the IP is no longer present
      refute render(view) =~ "192.168.1.100"
    end

    test "allows editing the description", %{conn: conn, admin: admin} do
      {:ok, _entry} =
        IPWhitelistService.add_to_whitelist(
          %{ip_address: "192.168.1.100", description: "Old description"},
          admin.id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      # Click the "Edit" link (live patch)
      html = view |> element("a", "Edit") |> render_click()

      # Modal should be displayed with form
      assert html =~ "ip-form"

      # Edit the description
      view
      |> form("#ip-form", ip_whitelist: %{description: "New description"})
      |> render_submit()

      # Verify the new description
      assert render(view) =~ "New description"
      refute render(view) =~ "Old description"
    end

    test "displays the creator of each entry", %{conn: conn, admin: admin} do
      {:ok, _} =
        IPWhitelistService.add_to_whitelist(
          %{ip_address: "192.168.1.100"},
          admin.id
        )

      {:ok, _view, html} = live(conn, ~p"/admin/ip-whitelist")

      assert html =~ admin.email
    end

    test "displays the creation date", %{conn: conn, admin: admin} do
      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: "192.168.1.100"}, admin.id)

      {:ok, _view, html} = live(conn, ~p"/admin/ip-whitelist")

      # Should display a date (relative or absolute format)
      assert html =~ ~r/\d{4}-\d{2}-\d{2}|\d+ (second|minute|hour|day)s? ago/
    end

    test "requires authentication", %{conn: _conn} do
      conn = build_conn()

      # Should redirect to login
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/ip-whitelist")
      assert path == "/login"
    end
  end
end
