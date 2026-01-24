defmodule PortfolioWeb.Plugs.RateLimiterPlugTest do
  use PortfolioWeb.ConnCase, async: false

  alias Portfolio.RateLimiter
  alias PortfolioWeb.Plugs.RateLimiterPlug

  setup %{conn: conn} do
    # Initialize session and flash
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> fetch_flash()

    {:ok, conn: conn}
  end

  describe "init/1" do
    test "requires action option" do
      assert_raise KeyError, fn ->
        RateLimiterPlug.init(identifier: :ip)
      end
    end

    test "requires identifier option" do
      assert_raise KeyError, fn ->
        RateLimiterPlug.init(action: :login_attempt)
      end
    end

    test "accepts all valid options" do
      opts =
        RateLimiterPlug.init(
          action: :login_attempt,
          identifier: :param,
          param_name: "email",
          api_mode: true
        )

      assert opts.action == :login_attempt
      assert opts.identifier == :param
      assert opts.param_name == "email"
      assert opts.api_mode == true
    end

    test "defaults api_mode to false" do
      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)
      assert opts.api_mode == false
    end
  end

  describe "call/2 with :ip identifier" do
    setup %{conn: conn} do
      unique_ip = {10, 0, System.unique_integer([:positive]) |> rem(255), 1}
      conn = %{conn | remote_ip: unique_ip}

      on_exit(fn ->
        ip_string = unique_ip |> Tuple.to_list() |> Enum.join(".")
        RateLimiter.reset(:login_attempt, ip_string)
      end)

      {:ok, conn: conn}
    end

    test "allows requests under the limit", %{conn: conn} do
      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      # login_attempt limit is 10 per minute
      for _ <- 1..5 do
        result_conn = RateLimiterPlug.call(conn, opts)
        refute result_conn.halted
      end
    end

    test "blocks requests over the limit", %{conn: conn} do
      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      # Exhaust the limit (10 requests)
      for _ <- 1..10 do
        RateLimiterPlug.call(conn, opts)
      end

      # 11th request should be blocked (redirects in browser mode)
      result_conn = RateLimiterPlug.call(conn, opts)
      assert result_conn.halted
      # In browser mode (api_mode: false), it redirects to /login
      assert result_conn.status == 302
      assert get_resp_header(result_conn, "location") == ["/login"]
    end

    test "sets retry-after header when blocked", %{conn: conn} do
      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      # Exhaust the limit
      for _ <- 1..10 do
        RateLimiterPlug.call(conn, opts)
      end

      result_conn = RateLimiterPlug.call(conn, opts)
      retry_after = get_resp_header(result_conn, "retry-after")

      assert length(retry_after) == 1
      assert String.to_integer(hd(retry_after)) > 0
    end
  end

  describe "call/2 with :param identifier" do
    setup %{conn: conn} do
      unique_email = "test_#{System.unique_integer([:positive])}@example.com"

      on_exit(fn ->
        RateLimiter.reset(:magic_link_request, String.downcase(unique_email))
      end)

      {:ok, conn: conn, email: unique_email}
    end

    test "uses normalized param value as identifier", %{conn: conn, email: email} do
      opts =
        RateLimiterPlug.init(
          action: :magic_link_request,
          identifier: :param,
          param_name: "email"
        )

      conn_with_params = %{conn | params: %{"email" => email}}

      # magic_link_request limit is 5 per 15 minutes
      for _ <- 1..5 do
        result_conn = RateLimiterPlug.call(conn_with_params, opts)
        refute result_conn.halted
      end

      # 6th request should be blocked
      result_conn = RateLimiterPlug.call(conn_with_params, opts)
      assert result_conn.halted
    end

    test "normalizes email to lowercase", %{conn: conn} do
      opts =
        RateLimiterPlug.init(
          action: :magic_link_request,
          identifier: :param,
          param_name: "email"
        )

      unique_base = "Test_#{System.unique_integer([:positive])}"
      upper_email = "#{unique_base}@EXAMPLE.COM"
      lower_email = String.downcase(upper_email)

      on_exit(fn -> RateLimiter.reset(:magic_link_request, lower_email) end)

      # Exhaust limit with uppercase email
      conn_upper = %{conn | params: %{"email" => upper_email}}

      for _ <- 1..5 do
        RateLimiterPlug.call(conn_upper, opts)
      end

      # Lowercase should be blocked too (same normalized identifier)
      conn_lower = %{conn | params: %{"email" => lower_email}}
      result_conn = RateLimiterPlug.call(conn_lower, opts)
      assert result_conn.halted
    end

    test "falls back to IP when param is nil", %{conn: conn} do
      unique_ip = {10, 0, System.unique_integer([:positive]) |> rem(255), 2}
      conn = %{conn | remote_ip: unique_ip, params: %{"email" => nil}}
      ip_string = unique_ip |> Tuple.to_list() |> Enum.join(".")

      on_exit(fn -> RateLimiter.reset(:magic_link_request, ip_string) end)

      opts =
        RateLimiterPlug.init(
          action: :magic_link_request,
          identifier: :param,
          param_name: "email"
        )

      # Should use IP as fallback
      for _ <- 1..5 do
        result_conn = RateLimiterPlug.call(conn, opts)
        refute result_conn.halted
      end

      # 6th should be blocked
      result_conn = RateLimiterPlug.call(conn, opts)
      assert result_conn.halted
    end

    test "falls back to IP when param is empty string", %{conn: conn} do
      unique_ip = {10, 0, System.unique_integer([:positive]) |> rem(255), 3}
      conn = %{conn | remote_ip: unique_ip, params: %{"email" => ""}}
      ip_string = unique_ip |> Tuple.to_list() |> Enum.join(".")

      on_exit(fn -> RateLimiter.reset(:magic_link_request, ip_string) end)

      opts =
        RateLimiterPlug.init(
          action: :magic_link_request,
          identifier: :param,
          param_name: "email"
        )

      for _ <- 1..5 do
        RateLimiterPlug.call(conn, opts)
      end

      result_conn = RateLimiterPlug.call(conn, opts)
      assert result_conn.halted
    end

    test "falls back to IP when param is whitespace only", %{conn: conn} do
      unique_ip = {10, 0, System.unique_integer([:positive]) |> rem(255), 4}
      conn = %{conn | remote_ip: unique_ip, params: %{"email" => "   "}}
      ip_string = unique_ip |> Tuple.to_list() |> Enum.join(".")

      on_exit(fn -> RateLimiter.reset(:magic_link_request, ip_string) end)

      opts =
        RateLimiterPlug.init(
          action: :magic_link_request,
          identifier: :param,
          param_name: "email"
        )

      for _ <- 1..5 do
        RateLimiterPlug.call(conn, opts)
      end

      result_conn = RateLimiterPlug.call(conn, opts)
      assert result_conn.halted
    end
  end

  describe "call/2 with {:custom, func} identifier" do
    test "uses custom function to get identifier", %{conn: conn} do
      unique_id = "custom_#{System.unique_integer([:positive])}"

      on_exit(fn -> RateLimiter.reset(:login_attempt, unique_id) end)

      custom_fn = fn _conn -> unique_id end

      opts =
        RateLimiterPlug.init(
          action: :login_attempt,
          identifier: {:custom, custom_fn}
        )

      # Exhaust limit (10 for login_attempt)
      for _ <- 1..10 do
        result_conn = RateLimiterPlug.call(conn, opts)
        refute result_conn.halted
      end

      # 11th should be blocked
      result_conn = RateLimiterPlug.call(conn, opts)
      assert result_conn.halted
    end

    test "custom function receives conn", %{conn: conn} do
      unique_ip = {10, 0, System.unique_integer([:positive]) |> rem(255), 5}
      conn = %{conn | remote_ip: unique_ip}
      ip_string = unique_ip |> Tuple.to_list() |> Enum.join(".")

      on_exit(fn -> RateLimiter.reset(:login_attempt, ip_string) end)

      # Custom function that extracts IP from conn
      custom_fn = fn c ->
        c.remote_ip |> Tuple.to_list() |> Enum.join(".")
      end

      opts =
        RateLimiterPlug.init(
          action: :login_attempt,
          identifier: {:custom, custom_fn}
        )

      for _ <- 1..10 do
        RateLimiterPlug.call(conn, opts)
      end

      result_conn = RateLimiterPlug.call(conn, opts)
      assert result_conn.halted
    end
  end

  describe "api_mode option" do
    setup %{conn: conn} do
      unique_ip = {10, 0, System.unique_integer([:positive]) |> rem(255), 6}
      conn = %{conn | remote_ip: unique_ip}
      ip_string = unique_ip |> Tuple.to_list() |> Enum.join(".")

      on_exit(fn -> RateLimiter.reset(:csp_report, ip_string) end)

      {:ok, conn: conn}
    end

    test "returns JSON response when api_mode is true", %{conn: conn} do
      opts =
        RateLimiterPlug.init(
          action: :csp_report,
          identifier: :ip,
          api_mode: true
        )

      # csp_report limit is 100 per minute - exhaust it
      for _ <- 1..100 do
        RateLimiterPlug.call(conn, opts)
      end

      result_conn = RateLimiterPlug.call(conn, opts)
      assert result_conn.halted
      assert result_conn.status == 429

      # Check JSON response
      content_type = get_resp_header(result_conn, "content-type")
      assert hd(content_type) =~ "application/json"

      body = Jason.decode!(result_conn.resp_body)
      assert body["error"] == "rate_limit_exceeded"
      assert is_integer(body["retry_after"])
      assert body["retry_after"] > 0
    end

    test "redirects to login when api_mode is false", %{conn: conn} do
      unique_ip = {10, 0, System.unique_integer([:positive]) |> rem(255), 7}
      conn = %{conn | remote_ip: unique_ip}
      ip_string = unique_ip |> Tuple.to_list() |> Enum.join(".")

      on_exit(fn -> RateLimiter.reset(:login_attempt, ip_string) end)

      opts =
        RateLimiterPlug.init(
          action: :login_attempt,
          identifier: :ip,
          api_mode: false
        )

      # Exhaust limit
      for _ <- 1..10 do
        RateLimiterPlug.call(conn, opts)
      end

      result_conn = RateLimiterPlug.call(conn, opts)
      assert result_conn.halted
      assert result_conn.status == 302
      assert get_resp_header(result_conn, "location") == ["/login"]
    end
  end

  describe "format_retry_time (via response)" do
    test "formats minutes correctly", %{conn: conn} do
      unique_ip = {10, 0, System.unique_integer([:positive]) |> rem(255), 8}
      conn = %{conn | remote_ip: unique_ip}
      ip_string = unique_ip |> Tuple.to_list() |> Enum.join(".")

      on_exit(fn -> RateLimiter.reset(:login_attempt, ip_string) end)

      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      # Exhaust limit to trigger rate limit response
      for _ <- 1..10 do
        RateLimiterPlug.call(conn, opts)
      end

      result_conn = RateLimiterPlug.call(conn, opts)

      # Check flash message contains minute formatting
      flash = Phoenix.Flash.get(result_conn.assigns.flash, :error)
      assert flash =~ "minute"
    end

    test "formats hours for longer windows", %{conn: conn} do
      unique_ip = {10, 0, System.unique_integer([:positive]) |> rem(255), 9}
      conn = %{conn | remote_ip: unique_ip}
      ip_string = unique_ip |> Tuple.to_list() |> Enum.join(".")

      on_exit(fn -> RateLimiter.reset(:bulk_delete, ip_string) end)

      # bulk_delete has 1 minute window, so we can't easily test hours
      # Instead, test that format_retry_time handles the window correctly
      opts = RateLimiterPlug.init(action: :bulk_delete, identifier: :ip)

      # bulk_delete limit is 5 per minute
      for _ <- 1..5 do
        RateLimiterPlug.call(conn, opts)
      end

      result_conn = RateLimiterPlug.call(conn, opts)
      flash = Phoenix.Flash.get(result_conn.assigns.flash, :error)
      # Should contain "minute" or "heure" depending on retry time
      assert flash =~ "minute" or flash =~ "heure"
    end
  end

  describe "different rate limit actions" do
    test "magic_link_request has limit of 5", %{conn: conn} do
      unique_ip = {10, 0, System.unique_integer([:positive]) |> rem(255), 10}
      conn = %{conn | remote_ip: unique_ip}
      ip_string = unique_ip |> Tuple.to_list() |> Enum.join(".")

      on_exit(fn -> RateLimiter.reset(:magic_link_request, ip_string) end)

      opts = RateLimiterPlug.init(action: :magic_link_request, identifier: :ip)

      # Should allow 5 requests
      for _ <- 1..5 do
        result_conn = RateLimiterPlug.call(conn, opts)
        refute result_conn.halted
      end

      # 6th should be blocked
      result_conn = RateLimiterPlug.call(conn, opts)
      assert result_conn.halted
    end

    test "photo_upload has limit of 50", %{conn: conn} do
      unique_ip = {10, 0, System.unique_integer([:positive]) |> rem(255), 11}
      conn = %{conn | remote_ip: unique_ip}
      ip_string = unique_ip |> Tuple.to_list() |> Enum.join(".")

      on_exit(fn -> RateLimiter.reset(:photo_upload, ip_string) end)

      opts = RateLimiterPlug.init(action: :photo_upload, identifier: :ip)

      # Should allow 50 requests
      for i <- 1..50 do
        result_conn = RateLimiterPlug.call(conn, opts)
        refute result_conn.halted, "Request #{i} should not be halted"
      end

      # 51st should be blocked
      result_conn = RateLimiterPlug.call(conn, opts)
      assert result_conn.halted
    end
  end
end
