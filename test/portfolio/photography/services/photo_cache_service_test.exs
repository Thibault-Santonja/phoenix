defmodule Portfolio.Photography.Services.PhotoCacheServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Photography.Services.PhotoCacheService

  describe "get_processing_stats/1" do
    test "returns processing stats" do
      stats = PhotoCacheService.get_processing_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :pending)
      assert Map.has_key?(stats, :completed)
      assert Map.has_key?(stats, :failed)
      assert Map.has_key?(stats, :total)
    end

    test "returns non-negative integers for all stats" do
      stats = PhotoCacheService.get_processing_stats()

      assert stats.pending >= 0
      assert stats.completed >= 0
      assert stats.failed >= 0
      assert stats.total >= 0
    end

    test "total equals sum of other statuses" do
      stats = PhotoCacheService.get_processing_stats()

      assert stats.total == stats.pending + stats.completed + stats.failed
    end

    test "skip_cache option bypasses cache" do
      # Both calls should return the same structure
      cached = PhotoCacheService.get_processing_stats()
      uncached = PhotoCacheService.get_processing_stats(skip_cache: true)

      assert is_map(cached)
      assert is_map(uncached)
      assert Map.keys(cached) == Map.keys(uncached)
    end
  end

  describe "invalidate_stats_cache/0" do
    test "returns :ok" do
      assert :ok = PhotoCacheService.invalidate_stats_cache()
    end

    test "can be called multiple times without error" do
      assert :ok = PhotoCacheService.invalidate_stats_cache()
      assert :ok = PhotoCacheService.invalidate_stats_cache()
    end
  end
end
