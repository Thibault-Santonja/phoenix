defmodule PortfolioWeb.PageControllerTest do
  use PortfolioWeb.ConnCase, async: true

  describe "subdomain_redirect/2" do
    test "redirects to photo subdomain", %{conn: conn} do
      conn = get(conn, ~p"/photo")

      assert redirected_to(conn) == "https://photo.thibaultsan.com"
    end

    test "redirects to tech subdomain", %{conn: conn} do
      conn = get(conn, ~p"/tech")

      assert redirected_to(conn) == "https://tech.thibaultsan.com"
    end

    test "redirects to amvcc subdomain", %{conn: conn} do
      conn = get(conn, ~p"/amvcc")

      assert redirected_to(conn) == "https://amvcc.thibaultsan.com"
    end

    test "returns 404 for unknown subdomain", %{conn: conn} do
      conn = get(conn, "/unknown-subdomain")

      assert html_response(conn, 404)
    end

    test "prevents open redirect attacks with malicious subdomain", %{conn: conn} do
      # Attempt to inject a malicious redirect
      conn = get(conn, "/malicious.example.com")

      # Should return 404, not redirect
      assert html_response(conn, 404)
    end
  end
end
