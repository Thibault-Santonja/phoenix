defmodule PortfolioWeb.Photography.TimelineLiveTest do
  use PortfolioWeb.ConnCase
  import Phoenix.LiveViewTest

  defp open_subdomain(%{conn: conn}) do
    {:error, {:redirect, %{to: subdomain}}} = live(conn, ~p"/photo")

    %{conn: conn, subdomain: subdomain}
  end

  describe "Photography timeline index" do
    setup [:open_subdomain]

    test "/timeline path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _timeline_live, html} = live(conn, subdomain <> "/timeline")
      assert html =~ "Thibault San Photographie"
    end

    test "redirection to home ", %{conn: conn, subdomain: subdomain} do
      {:ok, timeline_live, _html} = live(conn, subdomain <> "/timeline")

      timeline_live
      |> element("a", "Home")
      |> render_click()
      |> follow_redirect(conn, ~p"/")
    end
  end
end
