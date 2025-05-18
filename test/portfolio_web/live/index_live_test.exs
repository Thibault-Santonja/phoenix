defmodule PortfolioWeb.IndexLiveTest do
  use PortfolioWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "Website index" do
    test "/ path render default page", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, ~p"/")
      assert html =~ "Thibault Santonja"
    end
  end
end
