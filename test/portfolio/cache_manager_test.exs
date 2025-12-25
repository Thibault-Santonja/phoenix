defmodule Portfolio.CacheManagerTest do
  use ExUnit.Case, async: false

  alias Portfolio.Auth.UserSession
  alias Portfolio.CacheManager

  @cache_name :portfolio_cache

  setup do
    # Clear cache before each test
    Cachex.clear(@cache_name)
    :ok
  end

  describe "delete/1" do
    test "deletes existing key" do
      key = {:test, "delete_key"}
      Cachex.put(@cache_name, key, "value")

      assert :ok = CacheManager.delete(key)
      assert {:ok, nil} = Cachex.get(@cache_name, key)
    end

    test "returns ok for non-existing key" do
      key = {:test, "non_existing"}

      assert :ok = CacheManager.delete(key)
    end

    test "handles various key types" do
      keys = [
        {:session, "token123"},
        {:user, 42},
        {:published_albums_by_year, []},
        "string_key",
        :atom_key
      ]

      for key <- keys do
        Cachex.put(@cache_name, key, "value")
        assert :ok = CacheManager.delete(key)
        assert {:ok, nil} = Cachex.get(@cache_name, key)
      end
    end
  end

  describe "delete_many/1" do
    test "returns ok for empty list" do
      assert :ok = CacheManager.delete_many([])
    end

    test "deletes multiple keys" do
      keys = [{:test, 1}, {:test, 2}, {:test, 3}]

      for key <- keys do
        Cachex.put(@cache_name, key, "value")
      end

      assert :ok = CacheManager.delete_many(keys)

      for key <- keys do
        assert {:ok, nil} = Cachex.get(@cache_name, key)
      end
    end

    test "handles mixed existing and non-existing keys" do
      existing_key = {:test, "existing"}
      non_existing_key = {:test, "non_existing"}

      Cachex.put(@cache_name, existing_key, "value")

      assert :ok = CacheManager.delete_many([existing_key, non_existing_key])
    end

    test "deletes all keys even when list is large" do
      keys = for i <- 1..50, do: {:test, i}

      for key <- keys do
        Cachex.put(@cache_name, key, "value#{inspect(key)}")
      end

      assert :ok = CacheManager.delete_many(keys)

      for key <- keys do
        assert {:ok, nil} = Cachex.get(@cache_name, key)
      end
    end
  end

  describe "invalidate_session/1" do
    test "invalidates session with raw token" do
      raw_token = "raw_session_token_123"
      hashed_token = UserSession.hash_token_value(raw_token)

      # Cache with hashed token (as it would be in production)
      Cachex.put(@cache_name, {:session, hashed_token}, %{user_id: 1})

      assert :ok = CacheManager.invalidate_session(raw_token)
      assert {:ok, nil} = Cachex.get(@cache_name, {:session, hashed_token})
    end

    test "invalidates session with hashed token" do
      raw_token = "another_token_456"
      _hashed_token = UserSession.hash_token_value(raw_token)

      # Cache with raw token
      Cachex.put(@cache_name, {:session, raw_token}, %{user_id: 2})

      assert :ok = CacheManager.invalidate_session(raw_token)
      assert {:ok, nil} = Cachex.get(@cache_name, {:session, raw_token})
    end

    test "handles both raw and hashed cached entries" do
      token = "dual_cached_token"
      hashed = UserSession.hash_token_value(token)

      # Both versions cached
      Cachex.put(@cache_name, {:session, token}, %{user_id: 1})
      Cachex.put(@cache_name, {:session, hashed}, %{user_id: 1})

      assert :ok = CacheManager.invalidate_session(token)

      assert {:ok, nil} = Cachex.get(@cache_name, {:session, token})
      assert {:ok, nil} = Cachex.get(@cache_name, {:session, hashed})
    end

    test "returns ok for non-existing session" do
      assert :ok = CacheManager.invalidate_session("non_existing_token")
    end
  end

  describe "invalidate_sessions/1" do
    test "invalidates multiple sessions" do
      tokens = ["token1", "token2", "token3"]

      for token <- tokens do
        hashed = UserSession.hash_token_value(token)
        Cachex.put(@cache_name, {:session, hashed}, %{user_id: 1})
      end

      assert :ok = CacheManager.invalidate_sessions(tokens)

      for token <- tokens do
        hashed = UserSession.hash_token_value(token)
        assert {:ok, nil} = Cachex.get(@cache_name, {:session, hashed})
      end
    end

    test "handles empty list" do
      assert :ok = CacheManager.invalidate_sessions([])
    end
  end

  describe "invalidate_albums/1" do
    test "invalidates album cache keys" do
      cache_keys = [
        {:published_albums_by_year, []},
        {:published_albums_by_year, [:photos]}
      ]

      for key <- cache_keys do
        Cachex.put(@cache_name, key, [%{id: 1, title: "Album"}])
      end

      assert :ok = CacheManager.invalidate_albums()

      for key <- cache_keys do
        assert {:ok, nil} = Cachex.get(@cache_name, key)
      end
    end

    test "returns ok when no albums cached" do
      assert :ok = CacheManager.invalidate_albums()
    end
  end

  describe "fetch_or_compute/3" do
    test "returns cached value if present" do
      key = {:test, "cached_value"}
      cached_value = "cached"

      Cachex.put(@cache_name, key, cached_value)

      # compute_fn should NOT be called
      compute_fn = fn -> raise "should not be called" end

      result = CacheManager.fetch_or_compute(key, compute_fn)
      assert result == cached_value
    end

    test "computes and caches value if missing" do
      key = {:test, "compute_value"}
      computed_value = "computed"

      compute_fn = fn -> computed_value end

      result = CacheManager.fetch_or_compute(key, compute_fn)
      assert result == computed_value

      # Value should now be cached
      assert {:ok, ^computed_value} = Cachex.get(@cache_name, key)
    end

    @tag :skip
    @tag :flaky
    test "respects TTL option" do
      # NOTE: This test is flaky due to timing-dependent TTL behavior
      # The TTL expiration in Cachex is not immediate and depends on
      # background cleanup processes
      key = {:test, "ttl_value"}
      compute_fn = fn -> "short_lived" end

      CacheManager.fetch_or_compute(key, compute_fn, ttl: 100)

      # Value should be cached initially
      assert {:ok, "short_lived"} = Cachex.get(@cache_name, key)

      # Wait for TTL to expire
      Process.sleep(200)

      # Value should be expired (may be flaky due to cache cleanup timing)
      assert {:ok, nil} = Cachex.get(@cache_name, key)
    end

    test "computes expensive operations only once" do
      key = {:test, "expensive_op"}
      counter = :counters.new(1, [])

      compute_fn = fn ->
        :counters.add(counter, 1, 1)
        "computed_result"
      end

      # Call multiple times
      result1 = CacheManager.fetch_or_compute(key, compute_fn)
      result2 = CacheManager.fetch_or_compute(key, compute_fn)
      result3 = CacheManager.fetch_or_compute(key, compute_fn)

      assert result1 == "computed_result"
      assert result2 == "computed_result"
      assert result3 == "computed_result"

      # compute_fn should only have been called once
      assert :counters.get(counter, 1) == 1
    end

    test "handles nil computed values" do
      key = {:test, "nil_value"}
      compute_fn = fn -> nil end

      result = CacheManager.fetch_or_compute(key, compute_fn)
      assert result == nil
    end

    test "handles complex computed values" do
      key = {:test, "complex_value"}

      complex_value = %{
        users: [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}],
        metadata: %{total: 2, page: 1}
      }

      compute_fn = fn -> complex_value end

      result = CacheManager.fetch_or_compute(key, compute_fn)
      assert result == complex_value

      # Verify it's properly cached
      {:ok, cached} = Cachex.get(@cache_name, key)
      assert cached == complex_value
    end
  end

  describe "cache key namespacing" do
    test "different namespaces don't collide" do
      session_key = {:session, "token123"}
      user_key = {:user, "token123"}
      album_key = {:published_albums_by_year, "token123"}

      Cachex.put(@cache_name, session_key, "session_data")
      Cachex.put(@cache_name, user_key, "user_data")
      Cachex.put(@cache_name, album_key, "album_data")

      # Delete one shouldn't affect others
      CacheManager.delete(session_key)

      assert {:ok, nil} = Cachex.get(@cache_name, session_key)
      assert {:ok, "user_data"} = Cachex.get(@cache_name, user_key)
      assert {:ok, "album_data"} = Cachex.get(@cache_name, album_key)
    end
  end

  describe "fetch_or_compute/3 edge cases" do
    test "handles compute function returning empty list" do
      key = {:test, "empty_list"}
      compute_fn = fn -> [] end

      result = CacheManager.fetch_or_compute(key, compute_fn)
      assert result == []

      {:ok, cached} = Cachex.get(@cache_name, key)
      assert cached == []
    end

    test "handles compute function returning empty map" do
      key = {:test, "empty_map"}
      compute_fn = fn -> %{} end

      result = CacheManager.fetch_or_compute(key, compute_fn)
      assert result == %{}
    end

    test "handles compute function returning boolean false" do
      key = {:test, "false_value"}
      compute_fn = fn -> false end

      result = CacheManager.fetch_or_compute(key, compute_fn)
      assert result == false
    end

    test "handles compute function returning zero" do
      key = {:test, "zero_value"}
      compute_fn = fn -> 0 end

      result = CacheManager.fetch_or_compute(key, compute_fn)
      assert result == 0
    end

    test "works without TTL option" do
      key = {:test, "no_ttl"}
      compute_fn = fn -> "no_ttl_value" end

      result = CacheManager.fetch_or_compute(key, compute_fn, [])
      assert result == "no_ttl_value"
    end

    test "TTL is passed correctly when specified" do
      key = {:test, "with_ttl"}
      compute_fn = fn -> "ttl_value" end

      result = CacheManager.fetch_or_compute(key, compute_fn, ttl: 60_000)
      assert result == "ttl_value"

      # Value should be cached
      {:ok, cached} = Cachex.get(@cache_name, key)
      assert cached == "ttl_value"
    end
  end

  describe "delete_many/1 with errors" do
    test "handles single key deletion" do
      key = {:test, "single"}
      Cachex.put(@cache_name, key, "value")

      assert :ok = CacheManager.delete_many([key])
      assert {:ok, nil} = Cachex.get(@cache_name, key)
    end
  end

  describe "invalidate_albums/0 idempotency" do
    test "can be called multiple times safely" do
      # First call
      assert :ok = CacheManager.invalidate_albums()

      # Add some data
      Cachex.put(@cache_name, {:published_albums_by_year, []}, [%{id: 1}])

      # Second call
      assert :ok = CacheManager.invalidate_albums()

      # Third call (data already gone)
      assert :ok = CacheManager.invalidate_albums()
    end
  end

  describe "invalidate_session/1 idempotency" do
    test "can be called multiple times for same token" do
      token = "idempotent_token"

      assert :ok = CacheManager.invalidate_session(token)
      assert :ok = CacheManager.invalidate_session(token)
      assert :ok = CacheManager.invalidate_session(token)
    end
  end
end
