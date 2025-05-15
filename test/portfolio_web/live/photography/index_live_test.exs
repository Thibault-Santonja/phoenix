defmodule PortfolioWeb.Photography.IndexLiveTest do
  use PortfolioWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "Photography index" do
    test "/ path render default page", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, "/photo")
      assert html =~ "Thibault San Photographie"
    end
  end
end
