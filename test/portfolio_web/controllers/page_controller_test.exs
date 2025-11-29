defmodule PortfolioWeb.PageControllerTest do
  use PortfolioWeb.ConnCase

  describe "subdomain_redirect/2" do
    test "GET /amvcc redirects to allowed subdomain", %{conn: conn} do
      conn = get(conn, ~p"/amvcc")
      assert html_response(conn, 302) =~ "https://amvcc.thibaultsan.com"
    end

    test "GET /photo redirects to allowed subdomain", %{conn: conn} do
      conn = get(conn, ~p"/photo")
      assert html_response(conn, 302) =~ "https://photo.thibaultsan.com"
    end

    test "GET /tech redirects to allowed subdomain", %{conn: conn} do
      conn = get(conn, ~p"/tech")
      assert html_response(conn, 302) =~ "https://tech.thibaultsan.com"
    end

    test "GET /unknown returns 404 for non-whitelisted subdomain", %{conn: conn} do
      conn = get(conn, ~p"/unknown")
      assert html_response(conn, 404)
    end

    test "GET /malicious does not redirect to arbitrary URLs", %{conn: conn} do
      conn = get(conn, ~p"/evil.com")
      assert html_response(conn, 404)
    end
  end
end
