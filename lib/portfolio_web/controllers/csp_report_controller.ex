defmodule PortfolioWeb.CSPReportController do
  @moduledoc """
  Controller for handling Content Security Policy violation reports.

  Receives CSP violation reports from browsers and logs them for security monitoring.
  This enables detection of XSS attempts and misconfigured CSP policies.

  ## Rate Limiting

  This endpoint is rate limited to 100 requests per minute per IP to prevent
  log flooding and denial of service attacks via fake CSP reports.
  """

  use PortfolioWeb, :controller

  require Logger

  plug PortfolioWeb.Plugs.RateLimiterPlug, action: :csp_report, identifier: :ip, api_mode: true

  @doc """
  Receives and logs CSP violation reports.

  Browsers send POST requests with JSON payloads containing violation details
  when a CSP policy is violated. This endpoint logs these violations for
  security monitoring and analysis.

  ## Request Format

  The browser sends a JSON body with a `csp-report` key:

      {
        "csp-report": {
          "document-uri": "https://example.com/page",
          "violated-directive": "script-src 'self'",
          "blocked-uri": "https://malicious.com/evil.js",
          "source-file": "https://example.com/page",
          "line-number": 42
        }
      }

  ## Response

  Always returns 204 No Content to acknowledge receipt.
  """
  @spec report(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def report(conn, params) do
    case params do
      %{"csp-report" => report} ->
        log_csp_violation(report, conn)

      _ ->
        Logger.warning("Received malformed CSP report",
          raw_params: inspect(params),
          remote_ip: format_ip(conn.remote_ip)
        )
    end

    send_resp(conn, 204, "")
  end

  defp log_csp_violation(report, conn) do
    Logger.warning("CSP Violation detected",
      document_uri: report["document-uri"],
      violated_directive: report["violated-directive"],
      blocked_uri: report["blocked-uri"],
      source_file: report["source-file"],
      line_number: report["line-number"],
      column_number: report["column-number"],
      original_policy: truncate(report["original-policy"], 200),
      disposition: report["disposition"],
      referrer: report["referrer"],
      remote_ip: format_ip(conn.remote_ip),
      user_agent: get_user_agent(conn)
    )
  end

  defp format_ip(ip) when is_tuple(ip) do
    ip |> :inet.ntoa() |> to_string()
  end

  defp format_ip(ip), do: inspect(ip)

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] -> truncate(ua, 100)
      [] -> "unknown"
    end
  end

  defp truncate(nil, _max), do: nil
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max) <> "..."
end
