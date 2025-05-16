defmodule PortfolioWeb.PageControllerTest do
  use PortfolioWeb.ConnCase

  test "GET /amvcc", %{conn: conn} do
    page = "amvcc"
    conn = get(conn, ~p"/" <> page)
    assert html_response(conn, 302) =~ "<a href=\"http://#{page}.www.example.com:80\">"
  end

  test "GET /photo", %{conn: conn} do
    page = "photo"
    conn = get(conn, ~p"/" <> page)
    assert html_response(conn, 302) =~ "<a href=\"http://#{page}.www.example.com:80\">"
  end
end
