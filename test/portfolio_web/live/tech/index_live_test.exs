defmodule PortfolioWeb.Tech.IndexLiveTest do
  use PortfolioWeb.ConnCase
  import Phoenix.LiveViewTest

  defp open_subdomain(%{conn: conn}) do
    {:error, {:redirect, %{to: subdomain}}} = live(conn, ~p"/tech")

    %{conn: conn, subdomain: subdomain}
  end

  describe "Tech blog index" do
    setup [:open_subdomain]

    test "/ path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _index_live, html} = live(conn, subdomain <> "/")
      assert html =~ "Thibault San"
    end

    test "/blog/ci path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _index_live, html} = live(conn, subdomain <> "/blog/ci")
      assert html =~ "CI"
    end

    test "/blog/kamal path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _index_live, html} = live(conn, subdomain <> "/blog/kamal")
      assert html =~ "Kamal"
    end
  end
end
