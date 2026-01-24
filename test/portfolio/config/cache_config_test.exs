defmodule Portfolio.Config.CacheConfigTest do
  use ExUnit.Case, async: true

  alias Portfolio.Config.CacheConfig

  describe "session_ttl/0" do
    test "returns default TTL of 1 hour" do
      assert CacheConfig.session_ttl() == :timer.hours(1)
    end

    test "can be overridden via application config" do
      original = Application.get_env(:portfolio, :cache)

      try do
        Application.put_env(:portfolio, :cache, session_ttl: :timer.minutes(30))
        assert CacheConfig.session_ttl() == :timer.minutes(30)
      after
        if original do
          Application.put_env(:portfolio, :cache, original)
        else
          Application.delete_env(:portfolio, :cache)
        end
      end
    end
  end

  describe "albums_ttl/0" do
    test "returns default TTL of 1 hour" do
      assert CacheConfig.albums_ttl() == :timer.hours(1)
    end

    test "can be overridden via application config" do
      original = Application.get_env(:portfolio, :cache)

      try do
        Application.put_env(:portfolio, :cache, albums_ttl: :timer.hours(2))
        assert CacheConfig.albums_ttl() == :timer.hours(2)
      after
        if original do
          Application.put_env(:portfolio, :cache, original)
        else
          Application.delete_env(:portfolio, :cache)
        end
      end
    end
  end

  describe "mx_validation_ttl/0" do
    test "returns default TTL of 1 hour" do
      assert CacheConfig.mx_validation_ttl() == :timer.hours(1)
    end
  end

  describe "published_albums_key/1" do
    test "returns tuple with empty preloads by default" do
      assert CacheConfig.published_albums_key() == {:published_albums_by_year, []}
    end

    test "includes preloads in key when provided" do
      assert CacheConfig.published_albums_key(preloads: [:photos]) ==
               {:published_albums_by_year, [:photos]}
    end

    test "handles multiple preloads" do
      assert CacheConfig.published_albums_key(preloads: [:photos, :cover_photo]) ==
               {:published_albums_by_year, [:photos, :cover_photo]}
    end
  end

  describe "session_key/1" do
    test "returns tuple with hashed token" do
      assert CacheConfig.session_key("abc123hash") == {:session, "abc123hash"}
    end

    test "handles different token formats" do
      assert CacheConfig.session_key("") == {:session, ""}

      assert CacheConfig.session_key("long_token_value_here") ==
               {:session, "long_token_value_here"}
    end
  end

  describe "mx_validation_key/1" do
    test "returns tuple with domain" do
      assert CacheConfig.mx_validation_key("example.com") == {:mx_validation, "example.com"}
    end

    test "handles subdomains" do
      assert CacheConfig.mx_validation_key("mail.example.com") ==
               {:mx_validation, "mail.example.com"}
    end
  end
end
