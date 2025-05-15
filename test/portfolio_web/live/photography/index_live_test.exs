defmodule PortfolioWeb.Photography.IndexLiveTest do
  use PortfolioWeb.ConnCase
  import Phoenix.LiveViewTest

  defp open_subdomain(%{conn: conn}) do
    {:error, {:redirect, %{to: subdomain}}} = live(conn, ~p"/photo")

    %{conn: conn, subdomain: subdomain}
  end

  describe "Photography index" do
    setup [:open_subdomain]

    test "/ path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _index_live, html} = live(conn, subdomain <> "/")
      assert html =~ "Thibault San Photographie"
    end
  end
end
