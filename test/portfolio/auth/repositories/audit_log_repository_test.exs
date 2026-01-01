defmodule Portfolio.Auth.Repositories.AuditLogRepositoryTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Auth.AuditLog
  alias Portfolio.Auth.Repositories.AuditLogRepository

  import PortfolioTest.Fixtures.AuthFixtures

  # Helper to create an audit log entry
  defp create_audit_log(attrs) do
    performer = Keyword.get_lazy(attrs, :performed_by, &create_user/0)
    action = Keyword.get(attrs, :action, "user_role_changed")
    resource_type = Keyword.get(attrs, :resource_type, "User")
    resource_id = Keyword.get_lazy(attrs, :resource_id, &Ecto.UUID.generate/0)
    changes = Keyword.get(attrs, :changes, %{role: %{from: "user", to: "admin"}})

    %AuditLog{}
    |> AuditLog.changeset(%{
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      performed_by_id: performer.id,
      changes: changes
    })
    |> Portfolio.Repo.insert!()
  end

  describe "insert/1" do
    test "creates audit log with valid attrs" do
      performer = create_user()
      target_user_id = Ecto.UUID.generate()

      attrs = %{
        action: "user_role_changed",
        resource_type: "User",
        resource_id: target_user_id,
        performed_by_id: performer.id,
        changes: %{role: %{from: "user", to: "admin"}}
      }

      assert {:ok, log} = AuditLogRepository.insert(attrs)
      assert log.action == "user_role_changed"
      assert log.resource_type == "User"
      assert log.resource_id == target_user_id
      assert log.performed_by_id == performer.id
      assert log.changes == %{role: %{from: "user", to: "admin"}}
    end

    test "creates audit log with ip_whitelist actions" do
      performer = create_user()

      attrs = %{
        action: "ip_whitelist_added",
        resource_type: "IPWhitelist",
        resource_id: Ecto.UUID.generate(),
        performed_by_id: performer.id,
        changes: %{ip_address: "192.168.1.100"}
      }

      assert {:ok, log} = AuditLogRepository.insert(attrs)
      assert log.action == "ip_whitelist_added"
    end

    test "returns error with missing required fields" do
      assert {:error, changeset} = AuditLogRepository.insert(%{})
      refute changeset.valid?
    end

    test "returns error with empty action" do
      performer = create_user()

      attrs = %{
        action: "",
        resource_type: "User",
        resource_id: Ecto.UUID.generate(),
        performed_by_id: performer.id
      }

      assert {:error, changeset} = AuditLogRepository.insert(attrs)
      refute changeset.valid?
    end
  end

  describe "get_by_resource/3" do
    test "returns logs for specific resource" do
      performer = create_user()
      target_id = Ecto.UUID.generate()

      log1 = create_audit_log(performed_by: performer, resource_id: target_id)
      log2 = create_audit_log(performed_by: performer, resource_id: target_id)
      _other = create_audit_log(performed_by: performer)

      logs = AuditLogRepository.get_by_resource("User", target_id)
      ids = Enum.map(logs, & &1.id)

      assert log1.id in ids
      assert log2.id in ids
      assert length(logs) == 2
    end

    test "returns logs ordered by inserted_at descending" do
      performer = create_user()
      target_id = Ecto.UUID.generate()

      older = create_audit_log(performed_by: performer, resource_id: target_id)
      newer = create_audit_log(performed_by: performer, resource_id: target_id)

      # Manually set older timestamp (avoid Process.sleep)
      past_time =
        DateTime.utc_now()
        |> DateTime.add(-60, :second)

      older
      |> Ecto.Changeset.change(%{inserted_at: past_time})
      |> Portfolio.Repo.update!()

      [first | _] = AuditLogRepository.get_by_resource("User", target_id)
      assert first.id == newer.id
    end

    test "preloads performed_by association" do
      performer = create_user()
      target_id = Ecto.UUID.generate()
      create_audit_log(performed_by: performer, resource_id: target_id)

      [log | _] = AuditLogRepository.get_by_resource("User", target_id)
      assert log.performed_by.id == performer.id
      assert log.performed_by.email == performer.email
    end

    test "respects limit option" do
      performer = create_user()
      target_id = Ecto.UUID.generate()

      for _ <- 1..5 do
        create_audit_log(performed_by: performer, resource_id: target_id)
      end

      logs = AuditLogRepository.get_by_resource("User", target_id, limit: 3)
      assert length(logs) == 3
    end

    test "defaults to limit of 50" do
      performer = create_user()
      target_id = Ecto.UUID.generate()

      # Create more than default limit
      for _ <- 1..55 do
        create_audit_log(performed_by: performer, resource_id: target_id)
      end

      logs = AuditLogRepository.get_by_resource("User", target_id)
      assert length(logs) == 50
    end

    test "returns empty list when no logs for resource" do
      assert [] = AuditLogRepository.get_by_resource("User", Ecto.UUID.generate())
    end

    test "filters by resource_type" do
      performer = create_user()
      target_id = Ecto.UUID.generate()

      user_log =
        create_audit_log(performed_by: performer, resource_type: "User", resource_id: target_id)

      _ip_log =
        create_audit_log(
          performed_by: performer,
          resource_type: "IPWhitelist",
          resource_id: target_id,
          action: "ip_whitelist_added"
        )

      logs = AuditLogRepository.get_by_resource("User", target_id)

      assert length(logs) == 1
      assert hd(logs).id == user_log.id
    end
  end

  describe "get_by_performer/2" do
    test "returns logs performed by specific user" do
      performer1 = create_user()
      performer2 = create_user()

      log1 = create_audit_log(performed_by: performer1)
      log2 = create_audit_log(performed_by: performer1)
      _other = create_audit_log(performed_by: performer2)

      logs = AuditLogRepository.get_by_performer(performer1.id)
      ids = Enum.map(logs, & &1.id)

      assert log1.id in ids
      assert log2.id in ids
      assert length(logs) == 2
    end

    test "returns logs ordered by inserted_at descending" do
      performer = create_user()

      older = create_audit_log(performed_by: performer)
      newer = create_audit_log(performed_by: performer)

      # Manually set older timestamp (avoid Process.sleep)
      past_time =
        DateTime.utc_now()
        |> DateTime.add(-60, :second)

      older
      |> Ecto.Changeset.change(%{inserted_at: past_time})
      |> Portfolio.Repo.update!()

      [first | _] = AuditLogRepository.get_by_performer(performer.id)
      assert first.id == newer.id
    end

    test "preloads performed_by association" do
      performer = create_user()
      create_audit_log(performed_by: performer)

      [log | _] = AuditLogRepository.get_by_performer(performer.id)
      assert log.performed_by.id == performer.id
    end

    test "respects limit option" do
      performer = create_user()

      for _ <- 1..5 do
        create_audit_log(performed_by: performer)
      end

      logs = AuditLogRepository.get_by_performer(performer.id, limit: 3)
      assert length(logs) == 3
    end

    test "defaults to limit of 50" do
      performer = create_user()

      for _ <- 1..55 do
        create_audit_log(performed_by: performer)
      end

      logs = AuditLogRepository.get_by_performer(performer.id)
      assert length(logs) == 50
    end

    test "returns empty list when user has no logs" do
      user = create_user()

      assert [] = AuditLogRepository.get_by_performer(user.id)
    end
  end
end
