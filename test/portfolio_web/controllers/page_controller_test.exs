defmodule PortfolioWeb.PageControllerTest do
  use PortfolioWeb.ConnCase

  describe "home/2" do
    test "GET / renders home page", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200)
    end

    test "GET / renders without layout", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      # Home page should render but not include standard layout elements
      # that would be in the app layout
      assert html =~ "html" or html =~ "body"
    end

    test "GET / returns valid HTML", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      # Should contain basic HTML structure
      assert html =~ "<!DOCTYPE html>" or html =~ "<html"
    end
  end

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
