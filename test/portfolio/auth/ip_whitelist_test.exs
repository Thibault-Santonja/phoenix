defmodule Portfolio.Auth.IPWhitelistTest do
  use Portfolio.DataCase, async: true

  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Auth.IPWhitelist
  alias Portfolio.Repo

  describe "changeset/2" do
    test "validates with correct data" do
      admin = create_user(role: :admin)

      changeset =
        IPWhitelist.changeset(%IPWhitelist{}, %{
          ip_address: "192.168.1.100",
          description: "Office IP",
          created_by_id: admin.id
        })

      assert changeset.valid?
    end

    test "requires ip_address" do
      changeset = IPWhitelist.changeset(%IPWhitelist{}, %{})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).ip_address
    end

    test "validates IPv4 format" do
      admin = create_user(role: :admin)

      changeset =
        IPWhitelist.changeset(%IPWhitelist{}, %{
          ip_address: "invalid_ip",
          created_by_id: admin.id
        })

      refute changeset.valid?
      assert "has invalid format" in errors_on(changeset).ip_address
    end

    test "accepts valid IPv4 addresses" do
      admin = create_user(role: :admin)

      valid_ips = [
        "192.168.1.1",
        "10.0.0.1",
        "172.16.0.1",
        "8.8.8.8",
        "255.255.255.255"
      ]

      for ip <- valid_ips do
        changeset =
          IPWhitelist.changeset(%IPWhitelist{}, %{
            ip_address: ip,
            created_by_id: admin.id
          })

        assert changeset.valid?, "Expected #{ip} to be valid"
      end
    end

    test "accepts valid IPv6 addresses" do
      admin = create_user(role: :admin)

      valid_ips = [
        "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
        "2001:db8::1",
        "::1",
        "fe80::1"
      ]

      for ip <- valid_ips do
        changeset =
          IPWhitelist.changeset(%IPWhitelist{}, %{
            ip_address: ip,
            created_by_id: admin.id
          })

        assert changeset.valid?, "Expected #{ip} to be valid"
      end
    end

    test "rejects invalid IP addresses" do
      admin = create_user(role: :admin)

      invalid_ips = [
        "256.1.1.1",
        "192.168.1.1.1",
        "hello",
        "192.168.1.999",
        "not_an_ip",
        "999.999.999.999"
      ]

      for ip <- invalid_ips do
        changeset =
          IPWhitelist.changeset(%IPWhitelist{}, %{
            ip_address: ip,
            created_by_id: admin.id
          })

        refute changeset.valid?, "Expected #{ip} to be invalid"
      end
    end

    test "prevents duplicate IPs" do
      admin = create_user(role: :admin)
      ip = "192.168.1.100"

      # Create the first entry
      %IPWhitelist{}
      |> IPWhitelist.changeset(%{ip_address: ip, created_by_id: admin.id})
      |> Repo.insert!()

      # Try to create a duplicate
      changeset =
        %IPWhitelist{}
        |> IPWhitelist.changeset(%{ip_address: ip, created_by_id: admin.id})

      assert {:error, failed_changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(failed_changeset).ip_address
    end

    test "accepts an optional description" do
      admin = create_user(role: :admin)

      changeset =
        IPWhitelist.changeset(%IPWhitelist{}, %{
          ip_address: "192.168.1.100",
          description: "This is a long description for the IP address entry",
          created_by_id: admin.id
        })

      assert changeset.valid?
      assert get_change(changeset, :description) != nil
    end

    test "works without description" do
      admin = create_user(role: :admin)

      changeset =
        IPWhitelist.changeset(%IPWhitelist{}, %{
          ip_address: "192.168.1.100",
          created_by_id: admin.id
        })

      assert changeset.valid?
    end

    test "normalizes the IP address (trim whitespace)" do
      admin = create_user(role: :admin)

      changeset =
        IPWhitelist.changeset(%IPWhitelist{}, %{
          ip_address: "  192.168.1.100  ",
          created_by_id: admin.id
        })

      assert changeset.valid?
      assert get_change(changeset, :ip_address) == "192.168.1.100"
    end
  end

  describe "persistence" do
    test "can create a whitelist entry" do
      admin = create_user(role: :admin)

      entry =
        %IPWhitelist{}
        |> IPWhitelist.changeset(%{
          ip_address: "192.168.1.100",
          description: "Office",
          created_by_id: admin.id
        })
        |> Repo.insert!()

      assert entry.id != nil
      assert entry.ip_address == "192.168.1.100"
      assert entry.description == "Office"
      assert entry.created_by_id == admin.id
      assert entry.inserted_at != nil
    end

    test "preloads the created_by relationship" do
      admin = create_user(email: "admin@example.com", role: :admin)

      entry =
        %IPWhitelist{}
        |> IPWhitelist.changeset(%{
          ip_address: "192.168.1.100",
          created_by_id: admin.id
        })
        |> Repo.insert!()
        |> Repo.preload(:created_by)

      assert entry.created_by.id == admin.id
      assert entry.created_by.email == "admin@example.com"
    end
  end
end
