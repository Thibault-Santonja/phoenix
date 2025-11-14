defmodule Portfolio.Auth.IPWhitelistServiceTest do
  use Portfolio.DataCase, async: false

  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Auth.{IPWhitelist, IPWhitelistService}
  alias Portfolio.Repo

  setup do
    # Initialize cache before each test
    IPWhitelistService.init_cache()
    :ok
  end

  describe "list_whitelist/0" do
    test "returns all whitelist entries" do
      admin = create_user(role: :admin)

      create_whitelist_entry("192.168.1.100", admin.id)
      create_whitelist_entry("10.0.0.1", admin.id)

      entries = IPWhitelistService.list_whitelist()

      assert length(entries) == 2
    end

    test "returns an empty list if no entries" do
      assert IPWhitelistService.list_whitelist() == []
    end

    test "preloads the created_by relationship" do
      admin = create_user(email: "admin@example.com", role: :admin)
      create_whitelist_entry("192.168.1.100", admin.id)

      [entry] = IPWhitelistService.list_whitelist()

      assert entry.created_by.email == "admin@example.com"
    end
  end

  describe "add_to_whitelist/2" do
    test "adds an IP to the whitelist" do
      admin = create_user(role: :admin)

      assert {:ok, entry} =
               IPWhitelistService.add_to_whitelist(
                 %{
                   ip_address: "192.168.1.100",
                   description: "Office"
                 },
                 admin.id
               )

      assert entry.ip_address == "192.168.1.100"
      assert entry.description == "Office"
      assert entry.created_by_id == admin.id
    end

    test "returns an error if IP is invalid" do
      admin = create_user(role: :admin)

      assert {:error, changeset} =
               IPWhitelistService.add_to_whitelist(
                 %{ip_address: "invalid"},
                 admin.id
               )

      refute changeset.valid?
      assert "has invalid format" in errors_on(changeset).ip_address
    end

    test "prevents duplicates" do
      admin = create_user(role: :admin)
      ip = "192.168.1.100"

      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: ip}, admin.id)

      assert {:error, changeset} =
               IPWhitelistService.add_to_whitelist(%{ip_address: ip}, admin.id)

      assert "has already been taken" in errors_on(changeset).ip_address
    end
  end

  describe "remove_from_whitelist/1" do
    test "removes an entry from the whitelist" do
      admin = create_user(role: :admin)
      entry = create_whitelist_entry("192.168.1.100", admin.id)

      assert {:ok, deleted_entry} = IPWhitelistService.remove_from_whitelist(entry.id)

      assert deleted_entry.id == entry.id
      assert Repo.get(IPWhitelist, entry.id) == nil
    end

    test "returns an error if entry doesn't exist" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} = IPWhitelistService.remove_from_whitelist(fake_id)
    end
  end

  describe "whitelisted?/1" do
    test "returns true if IP is whitelisted" do
      admin = create_user(role: :admin)
      create_whitelist_entry("192.168.1.100", admin.id)

      assert IPWhitelistService.whitelisted?("192.168.1.100") == true
    end

    test "returns false if IP is not whitelisted" do
      assert IPWhitelistService.whitelisted?("192.168.1.200") == false
    end

    test "uses cache for performance" do
      admin = create_user(role: :admin)
      create_whitelist_entry("192.168.1.100", admin.id)

      # First call - should cache
      assert IPWhitelistService.whitelisted?("192.168.1.100") == true

      # Delete the entry from DB
      Repo.delete_all(IPWhitelist)

      # Cache should still return true (during TTL)
      assert IPWhitelistService.whitelisted?("192.168.1.100") == true
    end

    test "refreshes cache after adding" do
      admin = create_user(role: :admin)

      # IP is not whitelisted
      refute IPWhitelistService.whitelisted?("192.168.1.100")

      # Add the IP
      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: "192.168.1.100"}, admin.id)

      # Should immediately return true (cache refreshed)
      assert IPWhitelistService.whitelisted?("192.168.1.100")
    end

    test "refreshes cache after deletion" do
      admin = create_user(role: :admin)
      entry = create_whitelist_entry("192.168.1.100", admin.id)

      # IP is whitelisted
      assert IPWhitelistService.whitelisted?("192.168.1.100")

      # Remove the IP
      {:ok, _} = IPWhitelistService.remove_from_whitelist(entry.id)

      # Should immediately return false (cache refreshed)
      refute IPWhitelistService.whitelisted?("192.168.1.100")
    end
  end

  describe "get_whitelist_entry/1" do
    test "retrieves an entry by its ID" do
      admin = create_user(role: :admin)
      entry = create_whitelist_entry("192.168.1.100", admin.id)

      found = IPWhitelistService.get_whitelist_entry(entry.id)

      assert found.id == entry.id
      assert found.ip_address == "192.168.1.100"
    end

    test "returns nil if entry doesn't exist" do
      fake_id = Ecto.UUID.generate()

      assert IPWhitelistService.get_whitelist_entry(fake_id) == nil
    end
  end

  describe "update_whitelist_entry/2" do
    test "updates an entry's description" do
      admin = create_user(role: :admin)
      entry = create_whitelist_entry("192.168.1.100", admin.id, "Old description")

      assert {:ok, updated} =
               IPWhitelistService.update_whitelist_entry(entry, %{
                 description: "New description"
               })

      assert updated.description == "New description"
      assert updated.ip_address == "192.168.1.100"
    end

    test "prevents modifying the IP" do
      admin = create_user(role: :admin)
      entry = create_whitelist_entry("192.168.1.100", admin.id)

      # IP should not change even if we try
      {:ok, updated} =
        IPWhitelistService.update_whitelist_entry(entry, %{ip_address: "10.0.0.1"})

      assert updated.ip_address == "192.168.1.100"
    end

    test "returns an error if validation fails" do
      admin = create_user(role: :admin)
      entry = create_whitelist_entry("192.168.1.100", admin.id)

      # Description too long (more than 500 characters)
      long_desc = String.duplicate("a", 501)

      assert {:error, changeset} =
               IPWhitelistService.update_whitelist_entry(entry, %{description: long_desc})

      refute changeset.valid?
    end
  end

  # Helper to create a whitelist entry
  defp create_whitelist_entry(ip, created_by_id, description \\ nil) do
    attrs = %{ip_address: ip, created_by_id: created_by_id}
    attrs = if description, do: Map.put(attrs, :description, description), else: attrs

    entry =
      %IPWhitelist{}
      |> IPWhitelist.changeset(attrs)
      |> Repo.insert!()

    # Refresh cache after direct insertion
    IPWhitelistService.init_cache()

    entry
  end
end
