defmodule PortfolioWeb.CSPReportControllerTest do
  use PortfolioWeb.ConnCase, async: true

  import ExUnit.CaptureLog

  describe "POST /api/csp-report" do
    test "returns 204 and logs valid CSP violation report", %{conn: conn} do
      report = %{
        "csp-report" => %{
          "document-uri" => "https://example.com/page",
          "violated-directive" => "script-src 'self'",
          "blocked-uri" => "https://malicious.com/evil.js",
          "source-file" => "https://example.com/page",
          "line-number" => 42,
          "column-number" => 10,
          "original-policy" => "default-src 'self'; script-src 'self'",
          "disposition" => "enforce",
          "referrer" => "https://example.com/"
        }
      }

      log =
        capture_log(fn ->
          conn =
            conn
            |> put_req_header("content-type", "application/json")
            |> post("/api/csp-report", report)

          assert conn.status == 204
          assert conn.resp_body == ""
        end)

      # Logger outputs the message, metadata is in structured format
      assert log =~ "CSP Violation detected"
    end

    test "returns 204 for report with minimal fields", %{conn: conn} do
      report = %{
        "csp-report" => %{
          "violated-directive" => "style-src 'self'"
        }
      }

      log =
        capture_log(fn ->
          conn =
            conn
            |> put_req_header("content-type", "application/json")
            |> post("/api/csp-report", report)

          assert conn.status == 204
        end)

      assert log =~ "CSP Violation detected"
    end

    test "logs warning for malformed report", %{conn: conn} do
      malformed = %{"invalid" => "data"}

      log =
        capture_log(fn ->
          conn =
            conn
            |> put_req_header("content-type", "application/json")
            |> post("/api/csp-report", malformed)

          assert conn.status == 204
        end)

      assert log =~ "malformed CSP report"
    end

    test "returns 204 for empty request body", %{conn: conn} do
      log =
        capture_log(fn ->
          conn =
            conn
            |> put_req_header("content-type", "application/json")
            |> post("/api/csp-report", %{})

          assert conn.status == 204
        end)

      assert log =~ "malformed CSP report"
    end

    test "returns 204 for report with long original-policy", %{conn: conn} do
      long_policy = String.duplicate("a", 500)

      report = %{
        "csp-report" => %{
          "violated-directive" => "script-src",
          "original-policy" => long_policy
        }
      }

      log =
        capture_log(fn ->
          conn =
            conn
            |> put_req_header("content-type", "application/json")
            |> post("/api/csp-report", report)

          assert conn.status == 204
        end)

      assert log =~ "CSP Violation detected"
    end

    test "includes request_id in logs for traceability", %{conn: conn} do
      report = %{
        "csp-report" => %{
          "violated-directive" => "script-src 'self'"
        }
      }

      log =
        capture_log(fn ->
          conn
          |> put_req_header("content-type", "application/json")
          |> post("/api/csp-report", report)
        end)

      # Verify request_id is present in the log output
      assert log =~ "request_id="
    end
  end
end
