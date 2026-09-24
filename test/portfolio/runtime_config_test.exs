defmodule Portfolio.RuntimeConfigTest do
  @moduledoc """
  Guards the production runtime configuration.

  `config/runtime.exs` is only evaluated when a release boots, so a mistake in
  it is discovered on the server, during a deployment, and not before. These
  tests evaluate the very same file with `config_env() == :prod`, which makes
  the production configuration verifiable from the test suite.
  """
  use ExUnit.Case, async: false

  @runtime_config Path.expand("../../config/runtime.exs", __DIR__)

  @required_env %{
    "PHX_SERVER" => "true",
    "SECRET_KEY_BASE" => String.duplicate("a", 64),
    "DATABASE_URL" => "ecto://user:pass@localhost/portfolio_prod",
    "PHX_HOST" => "example.com",
    "LIVE_VIEW_SIGNING_SALT" => "sel-de-test",
    "SMTP_RELAY" => "smtp.example.com",
    "SMTP_USERNAME" => "expediteur@example.com",
    "SMTP_PASSWORD" => "mot-de-passe",
    "CATALOG_BASE_URL" => "http://photography:4000"
  }

  setup do
    previous = Map.new(@required_env, fn {name, _} -> {name, System.get_env(name)} end)
    System.put_env(@required_env)

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  defp read_prod_config, do: Config.Reader.read!(@runtime_config, env: :prod)

  defp mailer_config(config),
    do: config |> Keyword.fetch!(:portfolio) |> Keyword.fetch!(Portfolio.Mailer)

  describe "mailer" do
    test "does not fall back to the local adapter in production" do
      adapter = read_prod_config() |> mailer_config() |> Keyword.fetch!(:adapter)

      refute adapter == Swoosh.Adapters.Local,
             "the local adapter stores mails in memory: magic links would never be sent"

      assert adapter == Swoosh.Adapters.SMTP
    end

    test "carries the credentials taken from the environment" do
      mailer = read_prod_config() |> mailer_config()

      assert mailer[:relay] == "smtp.example.com"
      assert mailer[:username] == "expediteur@example.com"
      assert mailer[:password] == "mot-de-passe"
      assert mailer[:port] == 587
    end

    test "verifies the certificate of the relay" do
      tls_options = read_prod_config() |> mailer_config() |> Keyword.fetch!(:tls_options)

      assert tls_options[:verify] == :verify_peer
      assert tls_options[:server_name_indication] == ~c"smtp.example.com"
    end
  end

  describe "album catalog" do
    test "takes its base url from the environment, never from the localhost default" do
      catalog =
        read_prod_config() |> Keyword.fetch!(:portfolio) |> Keyword.fetch!(:album_catalog)

      # http://localhost:4000 is the portfolio itself: left in place, the
      # portfolio would query its own router, get a 404 and serve a broken
      # photography section.
      assert catalog[:base_url] == "http://photography:4000"
    end
  end

  describe "missing variables" do
    for name <- ~w(SECRET_KEY_BASE DATABASE_URL PHX_HOST LIVE_VIEW_SIGNING_SALT SMTP_RELAY
                   SMTP_USERNAME SMTP_PASSWORD CATALOG_BASE_URL) do
      test "booting without #{name} raises instead of starting a half configured release" do
        System.delete_env(unquote(name))

        assert_raise RuntimeError, ~r/#{unquote(name)}/, fn -> read_prod_config() end
      end
    end
  end
end
