defmodule PortfolioWeb.PageControllerTest do
  use PortfolioWeb.ConnCase, async: true

  describe "GET /" do
    test "renders home page", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert html_response(conn, 200) =~ "Thibault"
    end

    test "returns 200 status", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert conn.status == 200
    end
  end

  describe "GET /photo" do
    test "redirects to photo subdomain", %{conn: conn} do
      conn = get(conn, ~p"/photo")

      assert redirected_to(conn) == "https://photo.thibaultsan.com"
    end
  end

  describe "GET /tech" do
    test "redirects to tech subdomain", %{conn: conn} do
      conn = get(conn, ~p"/tech")

      assert redirected_to(conn) == "https://tech.thibaultsan.com"
    end
  end

  describe "GET /amvcc" do
    test "redirects to amvcc subdomain", %{conn: conn} do
      conn = get(conn, ~p"/amvcc")

      assert redirected_to(conn) == "https://amvcc.thibaultsan.com"
    end
  end

  describe "subdomain_redirect/2 security" do
    test "returns 404 for unknown subdomain paths", %{conn: conn} do
      conn = get(conn, "/unknown_subdomain")

      assert conn.status == 404
    end

    test "renders 404 error page with ErrorHTML view", %{conn: conn} do
      conn = get(conn, "/unknown_subdomain")

      assert html_response(conn, 404) =~ "404"
    end

    test "does not redirect to arbitrary URLs", %{conn: conn} do
      # Attempting to access a path that's not in the whitelist
      conn = get(conn, "/evil")

      assert conn.status == 404
      refute conn.status in [301, 302]
    end

    test "handles empty path segments gracefully", %{conn: conn} do
      # Edge case: path with no segments after base
      conn = get(conn, "/nonexistent")

      assert conn.status == 404
    end
  end
end
