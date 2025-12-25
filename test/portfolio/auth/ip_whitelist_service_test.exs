defmodule Portfolio.Auth.IPWhitelistServiceTest do
  use Portfolio.DataCase, async: false

  alias Portfolio.Auth.IPWhitelistService

  import PortfolioTest.Fixtures.AuthFixtures

  setup do
    # Initialize cache for tests
    IPWhitelistService.init_cache()
    :ok
  end

  describe "init_cache/0" do
    test "creates the ETS table if it doesn't exist" do
      # Should not raise
      assert :ok = IPWhitelistService.init_cache()
    end

    test "clears the cache if table already exists" do
      # Call twice - second should work
      assert :ok = IPWhitelistService.init_cache()
      assert :ok = IPWhitelistService.init_cache()
    end
  end

  describe "list_whitelist/0" do
    test "returns empty list when no entries" do
      assert [] = IPWhitelistService.list_whitelist()
    end

    test "returns all whitelist entries" do
      user = create_user()

      {:ok, _entry1} =
        IPWhitelistService.add_to_whitelist(%{ip_address: "192.168.1.1"}, user.id)

      {:ok, _entry2} =
        IPWhitelistService.add_to_whitelist(%{ip_address: "192.168.1.2"}, user.id)

      entries = IPWhitelistService.list_whitelist()
      assert length(entries) == 2
    end
  end

  describe "add_to_whitelist/2" do
    test "adds a valid IP address" do
      user = create_user()

      assert {:ok, entry} =
               IPWhitelistService.add_to_whitelist(
                 %{ip_address: "10.0.0.1", description: "Test"},
                 user.id
               )

      assert entry.ip_address == "10.0.0.1"
      assert entry.description == "Test"
    end

    test "adds IP with atom keys" do
      user = create_user()

      assert {:ok, entry} =
               IPWhitelistService.add_to_whitelist(
                 %{ip_address: "10.0.0.2"},
                 user.id
               )

      assert entry.ip_address == "10.0.0.2"
    end

    test "returns error for invalid IP format" do
      user = create_user()

      assert {:error, changeset} =
               IPWhitelistService.add_to_whitelist(
                 %{ip_address: "invalid-ip"},
                 user.id
               )

      assert changeset.valid? == false
    end

    test "returns error for duplicate IP" do
      user = create_user()

      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: "192.168.1.100"}, user.id)

      assert {:error, changeset} =
               IPWhitelistService.add_to_whitelist(%{ip_address: "192.168.1.100"}, user.id)

      assert changeset.valid? == false
    end
  end

  describe "remove_from_whitelist/1" do
    test "removes an existing entry" do
      user = create_user()
      {:ok, entry} = IPWhitelistService.add_to_whitelist(%{ip_address: "172.16.0.1"}, user.id)

      assert {:ok, deleted} = IPWhitelistService.remove_from_whitelist(entry.id)
      assert deleted.id == entry.id
    end

    test "returns error for non-existent entry" do
      assert {:error, :not_found} =
               IPWhitelistService.remove_from_whitelist(Ecto.UUID.generate())
    end
  end

  describe "get_whitelist_entry/1" do
    test "returns entry when found" do
      user = create_user()
      {:ok, entry} = IPWhitelistService.add_to_whitelist(%{ip_address: "10.10.10.1"}, user.id)

      result = IPWhitelistService.get_whitelist_entry(entry.id)
      assert result.id == entry.id
    end

    test "returns nil when not found" do
      assert nil == IPWhitelistService.get_whitelist_entry(Ecto.UUID.generate())
    end
  end

  describe "update_whitelist_entry/2" do
    test "updates the description" do
      user = create_user()

      {:ok, entry} =
        IPWhitelistService.add_to_whitelist(
          %{ip_address: "10.20.30.40", description: "Old"},
          user.id
        )

      assert {:ok, updated} =
               IPWhitelistService.update_whitelist_entry(entry, %{description: "New"})

      assert updated.description == "New"
    end
  end

  describe "whitelisted?/1" do
    test "returns false for non-whitelisted IP string" do
      refute IPWhitelistService.whitelisted?("1.2.3.4")
    end

    test "returns true for whitelisted IP string" do
      user = create_user()
      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: "5.6.7.8"}, user.id)

      assert IPWhitelistService.whitelisted?("5.6.7.8")
    end

    test "returns false for non-whitelisted IP tuple" do
      refute IPWhitelistService.whitelisted?({1, 2, 3, 4})
    end

    test "returns true for whitelisted IP tuple" do
      user = create_user()
      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: "9.10.11.12"}, user.id)

      assert IPWhitelistService.whitelisted?({9, 10, 11, 12})
    end

    test "handles IPv6 tuple for whitelisted IP" do
      user = create_user()
      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: "::1"}, user.id)

      # IPv6 loopback
      assert IPWhitelistService.whitelisted?({0, 0, 0, 0, 0, 0, 0, 1})
    end

    test "returns false for IPv6 tuple not whitelisted" do
      refute IPWhitelistService.whitelisted?({0, 0, 0, 0, 0, 0, 0, 2})
    end

    test "handles invalid IP tuple conversion gracefully" do
      # Test with malformed tuple - should not crash
      refute IPWhitelistService.whitelisted?({999, 999, 999, 999})
    end

    test "returns false when cache table is not initialized" do
      # Delete the ETS table
      :ets.delete(:ip_whitelist_cache)

      # Should return false without crashing
      refute IPWhitelistService.whitelisted?("192.168.1.1")

      # Reinitialize for other tests
      IPWhitelistService.init_cache()
    end

    test "uses cache for subsequent lookups" do
      user = create_user()
      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: "100.100.100.100"}, user.id)

      # First lookup populates cache
      assert IPWhitelistService.whitelisted?("100.100.100.100")

      # Second lookup should hit cache
      assert IPWhitelistService.whitelisted?("100.100.100.100")
    end

    test "cache is refreshed when IP is added" do
      user = create_user()

      # Add first IP
      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: "200.200.200.1"}, user.id)

      # Verify first IP is whitelisted
      assert IPWhitelistService.whitelisted?("200.200.200.1")

      # Add second IP
      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: "200.200.200.2"}, user.id)

      # Both should be whitelisted
      assert IPWhitelistService.whitelisted?("200.200.200.1")
      assert IPWhitelistService.whitelisted?("200.200.200.2")
    end

    test "handles empty cache gracefully" do
      # Ensure cache is initialized but empty
      IPWhitelistService.init_cache()

      # Should return false, not crash
      refute IPWhitelistService.whitelisted?("99.99.99.99")
    end
  end

  describe "add_to_whitelist/2 edge cases" do
    test "adds IP without description" do
      user = create_user()

      assert {:ok, entry} =
               IPWhitelistService.add_to_whitelist(
                 %{ip_address: "10.0.0.3"},
                 user.id
               )

      assert entry.ip_address == "10.0.0.3"
      assert is_nil(entry.description)
    end

    test "adds IPv6 address" do
      user = create_user()

      assert {:ok, entry} =
               IPWhitelistService.add_to_whitelist(
                 %{ip_address: "2001:db8::1", description: "IPv6 test"},
                 user.id
               )

      assert entry.ip_address == "2001:db8::1"
      assert entry.description == "IPv6 test"
    end

    test "normalizes IP address by trimming whitespace" do
      user = create_user()

      assert {:ok, entry} =
               IPWhitelistService.add_to_whitelist(
                 %{ip_address: "  10.0.0.4  "},
                 user.id
               )

      assert entry.ip_address == "10.0.0.4"
    end

    test "returns error for empty IP address" do
      user = create_user()

      assert {:error, changeset} =
               IPWhitelistService.add_to_whitelist(
                 %{ip_address: ""},
                 user.id
               )

      assert changeset.valid? == false
    end

    test "returns error for description longer than 500 characters" do
      user = create_user()
      long_description = String.duplicate("a", 501)

      assert {:error, changeset} =
               IPWhitelistService.add_to_whitelist(
                 %{ip_address: "10.0.0.5", description: long_description},
                 user.id
               )

      assert changeset.valid? == false
    end
  end

  describe "update_whitelist_entry/2 edge cases" do
    test "clears the description when set to nil" do
      user = create_user()

      {:ok, entry} =
        IPWhitelistService.add_to_whitelist(
          %{ip_address: "10.20.30.41", description: "Old"},
          user.id
        )

      assert {:ok, updated} =
               IPWhitelistService.update_whitelist_entry(entry, %{description: nil})

      assert is_nil(updated.description)
    end

    test "returns error for description longer than 500 characters" do
      user = create_user()

      {:ok, entry} =
        IPWhitelistService.add_to_whitelist(
          %{ip_address: "10.20.30.42", description: "Old"},
          user.id
        )

      long_description = String.duplicate("a", 501)

      assert {:error, changeset} =
               IPWhitelistService.update_whitelist_entry(entry, %{description: long_description})

      assert changeset.valid? == false
    end
  end

  describe "remove_from_whitelist/1 cache behavior" do
    test "removes entry from cache" do
      user = create_user()
      {:ok, entry} = IPWhitelistService.add_to_whitelist(%{ip_address: "172.16.0.2"}, user.id)

      # Verify IP is whitelisted
      assert IPWhitelistService.whitelisted?("172.16.0.2")

      # Remove entry
      {:ok, _deleted} = IPWhitelistService.remove_from_whitelist(entry.id)

      # Verify IP is no longer whitelisted
      refute IPWhitelistService.whitelisted?("172.16.0.2")
    end
  end
end
