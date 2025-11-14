defmodule PortfolioWeb.EndpointConfigTest do
  @moduledoc """
  Tests for Phoenix Endpoint configuration.

  These tests verify security-critical configuration such as session cookies,
  security headers, and environment-specific settings.

  Note: Session options are defined as module attributes in endpoint.ex.
  We test the endpoint source code directly and validate configuration values.
  """
  use ExUnit.Case, async: true

  describe "session cookie security configuration" do
    test "endpoint source code has http_only flag enabled" do
      # Read the endpoint source to verify configuration
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ "http_only: true",
             "Session cookie must have http_only flag enabled for XSS protection"
    end

    test "endpoint source code has same_site flag set to Lax" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ ~s(same_site: "Lax"),
             "Session cookie should have same_site=Lax for CSRF protection"
    end

    test "endpoint source code uses cookie store" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ "store: :cookie",
             "Session should be stored in cookies"
    end

    test "endpoint source code has signing_salt configured" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ ~r/signing_salt: "\w+"/,
             "Session signing_salt must be configured"
    end

    test "endpoint source code has compression enabled" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ "compress: true",
             "Session compression should be enabled to reduce cookie size"
    end

    test "endpoint source code has max_age configured from application config" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ "max_age: Application.compile_env",
             "max_age must be configured from application config"

      assert endpoint_source =~ ~r/max_age_seconds/,
             "max_age should use :max_age_seconds configuration key"
    end

    test "secure flag is environment-dependent in source code" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      # Verify that secure flag is set based on environment
      # Note: compile_env! is used (with !) to ensure the config is present
      assert endpoint_source =~ "secure: Application.compile_env!(:portfolio, :env) == :prod",
             "Session cookie MUST have secure flag enabled only in production (HTTPS only)"
    end

    test "session cookie key is properly namespaced in source code" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ ~s(key: "_portfolio_key"),
             "Session cookie key should be '_portfolio_key' to avoid conflicts"
    end
  end

  describe "security configuration validation" do
    test "current environment configuration" do
      # Verify we're running in test environment
      current_env = Application.get_env(:portfolio, :env)
      assert current_env == :test, "Tests should run in :test environment"
    end

    test "session max_age is configured" do
      max_age = Application.get_env(:portfolio, :session)[:max_age_seconds]

      assert max_age != nil, "Session max_age must be configured"
      assert is_integer(max_age), "max_age must be an integer"
      assert max_age > 0, "max_age must be positive"
      assert max_age == 24 * 60 * 60, "Expected max_age to be 24 hours (86400 seconds)"
    end

    test "session expiration is shorter than cookie max_age" do
      # Cookie max_age is 24 hours
      cookie_max_age = Application.get_env(:portfolio, :session)[:max_age_seconds]

      # Session expiration (inactivity timeout) is 2 hours
      session_expiration = Application.get_env(:portfolio, :auth)[:session_expiration_seconds]

      assert session_expiration < cookie_max_age,
             "Session expiration (#{session_expiration}s) should be shorter than cookie max_age (#{cookie_max_age}s)"

      # This is correct: cookie persists for 24h, but session expires after 2h of inactivity
      # This allows "remember me" functionality while maintaining security
    end
  end

  describe "production security requirements" do
    test "documents secure flag requirement for production" do
      # This test documents the expected production configuration
      # The actual validation happens via source code check above

      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      # Verify the pattern that enables secure flag in production
      assert endpoint_source =~ ":env) == :prod",
             """
             PRODUCTION REQUIREMENT VERIFIED:
             Session cookie MUST have secure flag enabled in production.

             Configuration: secure: Application.compile_env(:portfolio, :env) == :prod
             - In production (:env == :prod): secure = true (HTTPS only)
             - In test/dev (:env != :prod): secure = false (allow HTTP)

             This ensures cookies are only transmitted over HTTPS in production,
             protecting against man-in-the-middle attacks.
             """
    end

    test "endpoint uses Plug.Session with session options" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ "plug Plug.Session, @session_options",
             "Endpoint must use Plug.Session with @session_options"
    end

    test "LiveView sockets inherit session security" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      # Verify LiveView socket configuration references session_options
      assert endpoint_source =~ ~r/socket "\/live".*session: @session_options/s,
             "LiveView websocket must use secure session configuration"
    end
  end

  describe "security headers configuration" do
    test "endpoint implements put_secure_headers" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ "defp put_secure_headers",
             "Endpoint should have put_secure_headers function"
    end

    test "endpoint applies security headers plug" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ "plug :put_secure_headers",
             "Endpoint must apply security headers"
    end

    test "security headers include HSTS" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ "strict-transport-security",
             "Must include HSTS header for HTTPS enforcement"

      assert endpoint_source =~ "includeSubDomains",
             "HSTS should apply to all subdomains"
    end

    test "security headers include CSP" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ "content-security-policy",
             "Must include Content-Security-Policy header"
    end

    test "security headers include frame protection" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ "x-frame-options",
             "Must include X-Frame-Options header for clickjacking protection"
    end

    test "security headers include content type protection" do
      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ "x-content-type-options",
             "Must include X-Content-Type-Options header"
    end
  end

  describe "configuration consistency" do
    test "all session configuration keys are present in config" do
      session_config = Application.get_env(:portfolio, :session)

      assert session_config != nil, "Session configuration must exist"

      assert Keyword.has_key?(session_config, :max_age_seconds),
             "Session config must include max_age_seconds"
    end

    test "auth configuration includes session expiration" do
      auth_config = Application.get_env(:portfolio, :auth)

      assert auth_config != nil, "Auth configuration must exist"

      assert Keyword.has_key?(auth_config, :session_expiration_seconds),
             "Auth config must include session_expiration_seconds"

      assert Keyword.has_key?(auth_config, :activity_update_throttle_seconds),
             "Auth config must include activity_update_throttle_seconds"
    end

    test "endpoint is configured with correct OTP app" do
      # Verify endpoint module exists and is properly configured
      assert Code.ensure_loaded?(PortfolioWeb.Endpoint)

      endpoint_source = File.read!("lib/portfolio_web/endpoint.ex")

      assert endpoint_source =~ "use Phoenix.Endpoint, otp_app: :portfolio",
             "Endpoint must use correct OTP app"
    end
  end
end
