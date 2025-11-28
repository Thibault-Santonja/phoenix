defmodule PortfolioWeb.Plugs.SetLocaleTest do
  use PortfolioWeb.ConnCase, async: true

  alias PortfolioWeb.Plugs.SetLocale

  # Helper to set req_cookies which the plug pattern matches on
  defp with_locale_cookie(conn, locale) do
    %{conn | req_cookies: %{"locale" => locale}}
  end

  describe "init/1" do
    test "returns options unchanged" do
      opts = [some: :option]
      assert SetLocale.init(opts) == opts
    end

    test "handles empty options" do
      assert SetLocale.init([]) == []
    end
  end

  describe "call/2 with locale cookie" do
    test "sets locale from valid en cookie" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> with_locale_cookie("en")
        |> SetLocale.call([])

      assert get_session(conn, :locale) == "en"
    end

    test "sets locale from valid fr cookie" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> with_locale_cookie("fr")
        |> SetLocale.call([])

      assert get_session(conn, :locale) == "fr"
    end

    test "truncates locale to 2 characters" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> with_locale_cookie("en-US")
        |> SetLocale.call([])

      # Should extract "en" from "en-US"
      assert get_session(conn, :locale) == "en"
    end

    test "falls back to fr for unsupported locale" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> with_locale_cookie("de")
        |> SetLocale.call([])

      # German not supported, should default to French
      assert get_session(conn, :locale) == "fr"
    end

    test "falls back to fr for invalid locale string" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> with_locale_cookie("xx")
        |> SetLocale.call([])

      assert get_session(conn, :locale) == "fr"
    end
  end

  describe "call/2 without locale cookie" do
    test "defaults to fr when no cookie present" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> SetLocale.call([])

      assert get_session(conn, :locale) == "fr"
    end

    test "defaults to fr with empty req_cookies" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> Map.put(:req_cookies, %{})
        |> SetLocale.call([])

      assert get_session(conn, :locale) == "fr"
    end
  end
end
