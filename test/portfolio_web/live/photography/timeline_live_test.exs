defmodule PortfolioWeb.Photography.TimelineLiveTest do
  use PortfolioWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  defp open_subdomain(%{conn: conn}) do
    {:error, {:redirect, %{to: subdomain}}} = live(conn, ~p"/photo")

    %{conn: conn, subdomain: subdomain}
  end

  describe "Photography timeline index" do
    setup [:open_subdomain]

    test "/timeline path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _timeline_live, html} = live(conn, subdomain <> "/timeline")
      assert html =~ "Thibault Santonja"
    end

    test "redirection to home ", %{conn: conn, subdomain: subdomain} do
      {:ok, timeline_live, _html} = live(conn, subdomain <> "/timeline")

      # Use the main button (not the one in header) with hero icon
      timeline_live
      |> element("a.grow-0", "Accueil")
      |> render_click()
      |> follow_redirect(conn, ~p"/")
    end
  end
end
