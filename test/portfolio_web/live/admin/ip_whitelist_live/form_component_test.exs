defmodule PortfolioWeb.Admin.IPWhitelistLive.FormComponentTest do
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

  describe "FormComponent - New IP" do
    test "renders new IP form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      html = view |> element("a", "Add IP") |> render_click()

      assert html =~ "ip-form"
      assert html =~ "IP Address"
      assert html =~ "Description"
    end

    test "validates IPv4 format on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      view |> element("a", "Add IP") |> render_click()

      html =
        view
        |> form("#ip-form", ip_whitelist: %{ip_address: "invalid"})
        |> render_change()

      assert html =~ "has invalid format"
    end

    test "accepts valid IPv4 address", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      view |> element("a", "Add IP") |> render_click()

      html =
        view
        |> form("#ip-form", ip_whitelist: %{ip_address: "192.168.1.100"})
        |> render_change()

      refute html =~ "has invalid format"
    end

    test "accepts valid IPv6 address", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      view |> element("a", "Add IP") |> render_click()

      html =
        view
        |> form("#ip-form", ip_whitelist: %{ip_address: "2001:db8::1"})
        |> render_change()

      refute html =~ "has invalid format"
    end

    test "creates IP entry with description", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      view |> element("a", "Add IP") |> render_click()

      view
      |> form("#ip-form",
        ip_whitelist: %{
          ip_address: "10.0.0.50",
          description: "Development server"
        }
      )
      |> render_submit()

      html = render(view)
      assert html =~ "10.0.0.50"
      assert html =~ "Development server"
    end

    test "creates IP entry without description", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      view |> element("a", "Add IP") |> render_click()

      view
      |> form("#ip-form", ip_whitelist: %{ip_address: "172.16.0.1"})
      |> render_submit()

      assert render(view) =~ "172.16.0.1"
    end

    test "shows error for empty IP address", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      view |> element("a", "Add IP") |> render_click()

      html =
        view
        |> form("#ip-form", ip_whitelist: %{ip_address: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "required"
    end

    test "shows error for duplicate IP address", %{conn: conn, admin: admin} do
      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: "192.168.1.1"}, admin.id)

      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      view |> element("a", "Add IP") |> render_click()

      html =
        view
        |> form("#ip-form", ip_whitelist: %{ip_address: "192.168.1.1"})
        |> render_submit()

      assert html =~ "has already been taken"
    end

    test "validates various invalid IP formats", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      # Note: "192.168.1" is actually valid POSIX notation (parsed as 192.168.0.1)
      invalid_ips = [
        "256.256.256.256",
        "192.168.1.1.1",
        "abc.def.ghi.jkl",
        "192.168.1.1/24"
      ]

      for invalid_ip <- invalid_ips do
        view |> element("a", "Add IP") |> render_click()

        html =
          view
          |> form("#ip-form", ip_whitelist: %{ip_address: invalid_ip})
          |> render_change()

        assert html =~ "has invalid format",
               "Expected #{invalid_ip} to be invalid"
      end
    end
  end

  describe "FormComponent - Edit IP" do
    test "renders edit form with existing data", %{conn: conn, admin: admin} do
      {:ok, _} =
        IPWhitelistService.add_to_whitelist(
          %{ip_address: "192.168.1.100", description: "Existing entry"},
          admin.id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      html = view |> element("a", "Edit") |> render_click()

      assert html =~ "ip-form"
      assert html =~ "192.168.1.100"
      assert html =~ "Existing entry"
    end

    test "IP address field is disabled on edit", %{conn: conn, admin: admin} do
      {:ok, _} =
        IPWhitelistService.add_to_whitelist(%{ip_address: "192.168.1.100"}, admin.id)

      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      html = view |> element("a", "Edit") |> render_click()

      # IP field should be disabled
      assert html =~ "disabled"
    end

    test "updates description only", %{conn: conn, admin: admin} do
      {:ok, _} =
        IPWhitelistService.add_to_whitelist(
          %{ip_address: "192.168.1.100", description: "Old description"},
          admin.id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      view |> element("a", "Edit") |> render_click()

      view
      |> form("#ip-form", ip_whitelist: %{description: "Updated description"})
      |> render_submit()

      html = render(view)
      assert html =~ "192.168.1.100"
      assert html =~ "Updated description"
      refute html =~ "Old description"
    end

    test "allows clearing description", %{conn: conn, admin: admin} do
      {:ok, _} =
        IPWhitelistService.add_to_whitelist(
          %{ip_address: "192.168.1.100", description: "To be cleared"},
          admin.id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      view |> element("a", "Edit") |> render_click()

      view
      |> form("#ip-form", ip_whitelist: %{description: ""})
      |> render_submit()

      html = render(view)
      assert html =~ "192.168.1.100"
      refute html =~ "To be cleared"
    end
  end

  describe "FormComponent - Accessibility" do
    test "form has proper labels", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      html = view |> element("a", "Add IP") |> render_click()

      assert html =~ "IP Address"
      assert html =~ "Description"
    end

    test "form has proper placeholders", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      html = view |> element("a", "Add IP") |> render_click()

      assert html =~ "192.168.1.100" or html =~ "2001:db8::1"
    end

    test "save button shows loading state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ip-whitelist")

      html = view |> element("a", "Add IP") |> render_click()

      assert html =~ "phx-disable-with"
      assert html =~ "Saving"
    end
  end
end
