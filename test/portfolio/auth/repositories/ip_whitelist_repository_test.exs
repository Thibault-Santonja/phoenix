defmodule Portfolio.Auth.Repositories.IPWhitelistRepositoryTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Auth.IPWhitelist
  alias Portfolio.Auth.Repositories.IPWhitelistRepository

  import PortfolioTest.Fixtures.AuthFixtures

  # Helper to create an IP whitelist entry
  defp create_ip_whitelist(attrs) do
    admin = Keyword.get_lazy(attrs, :created_by, &create_user/0)
    ip_address = Keyword.get(attrs, :ip_address, "192.168.1.#{:rand.uniform(255)}")
    description = Keyword.get(attrs, :description, "Test IP")

    %IPWhitelist{}
    |> IPWhitelist.changeset(%{
      ip_address: ip_address,
      description: description,
      created_by_id: admin.id
    })
    |> Portfolio.Repo.insert!()
  end

  describe "list_all/0" do
    test "returns all whitelist entries" do
      admin = create_user()
      entry1 = create_ip_whitelist(created_by: admin)
      entry2 = create_ip_whitelist(created_by: admin)

      entries = IPWhitelistRepository.list_all()
      ids = Enum.map(entries, & &1.id)

      assert entry1.id in ids
      assert entry2.id in ids
    end

    test "returns entries ordered by inserted_at descending" do
      # Clear existing entries to have predictable ordering
      Portfolio.Repo.delete_all(IPWhitelist)

      admin = create_user()
      _older = create_ip_whitelist(created_by: admin, ip_address: "10.0.0.1")
      Process.sleep(50)
      _newer = create_ip_whitelist(created_by: admin, ip_address: "10.0.0.2")

      entries = IPWhitelistRepository.list_all()

      # Verify ordering: most recent first (descending by inserted_at)
      assert length(entries) == 2

      [first, second] = entries
      assert NaiveDateTime.compare(first.inserted_at, second.inserted_at) in [:gt, :eq]
    end

    test "preloads created_by association" do
      admin = create_user()
      create_ip_whitelist(created_by: admin)

      [entry | _] = IPWhitelistRepository.list_all()
      assert entry.created_by.id == admin.id
      assert entry.created_by.email == admin.email
    end

    test "returns empty list when no entries exist" do
      # Clear any existing entries for this test
      Portfolio.Repo.delete_all(IPWhitelist)

      assert [] = IPWhitelistRepository.list_all()
    end
  end

  describe "get/1" do
    test "returns entry when id exists" do
      admin = create_user()
      entry = create_ip_whitelist(created_by: admin)

      assert {:ok, found} = IPWhitelistRepository.get(entry.id)
      assert found.id == entry.id
      assert found.ip_address == entry.ip_address
    end

    test "preloads created_by association" do
      admin = create_user()
      entry = create_ip_whitelist(created_by: admin)

      assert {:ok, found} = IPWhitelistRepository.get(entry.id)
      assert found.created_by.id == admin.id
    end

    test "returns error when id does not exist" do
      assert {:error, :not_found} = IPWhitelistRepository.get(Ecto.UUID.generate())
    end
  end

  describe "list_ip_addresses/0" do
    test "returns only IP addresses as strings" do
      admin = create_user()
      create_ip_whitelist(created_by: admin, ip_address: "10.0.0.1")
      create_ip_whitelist(created_by: admin, ip_address: "10.0.0.2")

      addresses = IPWhitelistRepository.list_ip_addresses()

      assert "10.0.0.1" in addresses
      assert "10.0.0.2" in addresses
    end

    test "returns empty list when no entries exist" do
      Portfolio.Repo.delete_all(IPWhitelist)

      assert [] = IPWhitelistRepository.list_ip_addresses()
    end
  end

  describe "insert/1" do
    test "creates entry with valid attrs" do
      admin = create_user()

      attrs = %{
        ip_address: "192.168.100.50",
        description: "Office IP",
        created_by_id: admin.id
      }

      assert {:ok, entry} = IPWhitelistRepository.insert(attrs)
      assert entry.ip_address == "192.168.100.50"
      assert entry.description == "Office IP"
      assert entry.created_by_id == admin.id
    end

    test "returns error with invalid IP address" do
      admin = create_user()

      attrs = %{
        ip_address: "invalid-ip",
        created_by_id: admin.id
      }

      assert {:error, changeset} = IPWhitelistRepository.insert(attrs)
      refute changeset.valid?
    end

    test "returns error when IP address is missing" do
      admin = create_user()

      attrs = %{created_by_id: admin.id}

      assert {:error, changeset} = IPWhitelistRepository.insert(attrs)
      refute changeset.valid?
    end

    test "returns error on duplicate IP address" do
      admin = create_user()
      create_ip_whitelist(created_by: admin, ip_address: "192.168.1.100")

      attrs = %{
        ip_address: "192.168.1.100",
        created_by_id: admin.id
      }

      assert {:error, changeset} = IPWhitelistRepository.insert(attrs)
      refute changeset.valid?
    end
  end

  describe "update/2" do
    test "updates description" do
      admin = create_user()
      entry = create_ip_whitelist(created_by: admin, description: "Old description")

      assert {:ok, updated} =
               IPWhitelistRepository.update(entry, %{description: "New description"})

      assert updated.description == "New description"
    end

    test "does not allow updating IP address" do
      admin = create_user()
      entry = create_ip_whitelist(created_by: admin, ip_address: "192.168.1.1")

      # IP address should remain unchanged with update_changeset
      assert {:ok, updated} = IPWhitelistRepository.update(entry, %{ip_address: "10.0.0.1"})
      assert updated.ip_address == "192.168.1.1"
    end
  end

  describe "delete/1" do
    test "deletes entry" do
      admin = create_user()
      entry = create_ip_whitelist(created_by: admin)

      assert {:ok, deleted} = IPWhitelistRepository.delete(entry)
      assert deleted.id == entry.id
      assert {:error, :not_found} = IPWhitelistRepository.get(entry.id)
    end
  end
end
