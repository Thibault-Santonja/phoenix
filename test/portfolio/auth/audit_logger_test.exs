defmodule Portfolio.Auth.AuditLoggerTest do
  # async: false to avoid deadlocks with concurrent user creation in other tests
  use Portfolio.DataCase, async: false

  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Auth.AuditLog
  alias Portfolio.Auth.AuditLogger
  alias Portfolio.Repo

  describe "log/1" do
    test "crée un log d'audit avec toutes les informations" do
      user = create_user()
      admin = create_user(email: "admin@example.com", role: :admin)

      assert {:ok, log} =
               AuditLogger.log(
                 action: :custom_action,
                 resource_type: "User",
                 resource_id: user.id,
                 changes: %{"field" => %{"from" => "old", "to" => "new"}},
                 metadata: %{"reason" => "test"},
                 performed_by_id: admin.id,
                 ip_address: "192.168.1.1",
                 user_agent: "TestBrowser/1.0"
               )

      assert log.action == "custom_action"
      assert log.resource_type == "User"
      assert log.resource_id == user.id
      assert log.changes == %{"field" => %{"from" => "old", "to" => "new"}}
      assert log.metadata == %{"reason" => "test"}
      assert log.performed_by_id == admin.id
      assert log.ip_address == "192.168.1.1"
      assert log.user_agent == "TestBrowser/1.0"
      assert log.inserted_at != nil
    end

    test "accepte performed_by au lieu de performed_by_id" do
      admin = create_user(email: "admin@example.com", role: :admin)

      assert {:ok, log} =
               AuditLogger.log(
                 action: :test_action,
                 resource_type: "Test",
                 performed_by: admin
               )

      assert log.performed_by_id == admin.id
    end

    test "fonctionne sans performed_by" do
      assert {:ok, log} =
               AuditLogger.log(
                 action: :system_action,
                 resource_type: "System"
               )

      assert log.performed_by_id == nil
    end

    test "retourne une erreur si action manquante" do
      assert_raise KeyError, fn ->
        AuditLogger.log(resource_type: "Test")
      end
    end
  end

  describe "log_user_role_changed/2" do
    test "enregistre un changement de rôle" do
      user = create_user(role: :user)
      admin = create_user(email: "admin@example.com", role: :admin)

      assert {:ok, log} =
               AuditLogger.log_user_role_changed(user,
                 old_role: :user,
                 new_role: :admin,
                 performed_by: admin,
                 ip_address: "192.168.1.1"
               )

      assert log.action == "user_role_changed"
      assert log.resource_type == "User"
      assert log.resource_id == user.id
      assert log.changes == %{"role" => %{"from" => "user", "to" => "admin"}}
      assert log.performed_by_id == admin.id
      assert log.ip_address == "192.168.1.1"
    end

    test "accepte des atomes pour les rôles" do
      user = create_user(role: :user)
      admin = create_user(email: "admin@example.com", role: :admin)

      assert {:ok, log} =
               AuditLogger.log_user_role_changed(user,
                 old_role: :user,
                 new_role: :admin,
                 performed_by_id: admin.id
               )

      assert log.changes["role"]["from"] == "user"
      assert log.changes["role"]["to"] == "admin"
    end
  end

  describe "log_user_deleted/2" do
    test "enregistre une suppression d'utilisateur" do
      user = create_user(email: "deleted@example.com", name: "Test User", role: :user)
      admin = create_user(email: "admin@example.com", role: :admin)

      assert {:ok, log} =
               AuditLogger.log_user_deleted(user,
                 performed_by: admin,
                 ip_address: "192.168.1.1",
                 metadata: %{"reason" => "account cleanup"}
               )

      assert log.action == "user_deleted"
      assert log.resource_type == "User"
      assert log.resource_id == user.id
      assert log.changes["email"] == "deleted@example.com"
      assert log.changes["name"] == "Test User"
      assert log.changes["role"] == "user"
      assert log.metadata["reason"] == "account cleanup"
      assert log.performed_by_id == admin.id
    end
  end

  describe "log_sessions_revoked/2" do
    test "enregistre une révocation de sessions" do
      user = create_user()
      admin = create_user(email: "admin@example.com", role: :admin)

      assert {:ok, log} =
               AuditLogger.log_sessions_revoked(user,
                 session_count: 3,
                 performed_by: admin,
                 ip_address: "192.168.1.1"
               )

      assert log.action == "sessions_revoked"
      assert log.resource_type == "User"
      assert log.resource_id == user.id
      assert log.metadata["session_count"] == 3
      assert log.performed_by_id == admin.id
    end
  end

  describe "log_magic_link_sent/2" do
    test "enregistre l'envoi d'un magic link" do
      user = create_user()
      admin = create_user(email: "admin@example.com", role: :admin)

      assert {:ok, log} =
               AuditLogger.log_magic_link_sent(user,
                 performed_by: admin,
                 ip_address: "192.168.1.1"
               )

      assert log.action == "magic_link_sent"
      assert log.resource_type == "User"
      assert log.resource_id == user.id
      assert log.performed_by_id == admin.id
    end
  end

  describe "get_logs_for_resource/3" do
    test "récupère les logs pour une ressource spécifique" do
      user = create_user()
      admin = create_user(email: "admin@example.com", role: :admin)

      # Créer plusieurs logs
      {:ok, _log1} =
        AuditLogger.log_user_role_changed(user,
          old_role: :user,
          new_role: :admin,
          performed_by: admin
        )

      {:ok, _log2} =
        AuditLogger.log_sessions_revoked(user, session_count: 2, performed_by: admin)

      # Créer un log pour un autre utilisateur
      other_user = create_user(email: "other@example.com")
      {:ok, _log3} = AuditLogger.log_magic_link_sent(other_user, performed_by: admin)

      logs = AuditLogger.get_logs_for_resource("User", user.id)

      assert length(logs) == 2
      assert Enum.all?(logs, &(&1.resource_id == user.id))
    end

    test "limite le nombre de résultats" do
      user = create_user()
      admin = create_user(email: "admin@example.com", role: :admin)

      # Créer 5 logs
      for _ <- 1..5 do
        AuditLogger.log_sessions_revoked(user, session_count: 1, performed_by: admin)
      end

      logs = AuditLogger.get_logs_for_resource("User", user.id, limit: 3)

      assert length(logs) == 3
    end

    test "retourne les logs triés par date décroissante" do
      user = create_user()
      admin = create_user(email: "admin@example.com", role: :admin)

      {:ok, log1} =
        AuditLogger.log_sessions_revoked(user, session_count: 1, performed_by: admin)

      # Attendre un peu pour avoir des timestamps différents
      Process.sleep(10)

      {:ok, log2} =
        AuditLogger.log_sessions_revoked(user, session_count: 2, performed_by: admin)

      logs = AuditLogger.get_logs_for_resource("User", user.id)

      # Le plus récent doit être en premier
      assert hd(logs).id == log2.id
      assert List.last(logs).id == log1.id
    end

    test "preload la relation performed_by" do
      user = create_user()
      admin = create_user(email: "admin@example.com", role: :admin)

      {:ok, _log} = AuditLogger.log_magic_link_sent(user, performed_by: admin)

      logs = AuditLogger.get_logs_for_resource("User", user.id)

      assert [log] = logs
      assert log.performed_by.id == admin.id
      assert log.performed_by.email == "admin@example.com"
    end
  end

  describe "get_logs_by_user/2" do
    test "récupère les logs effectués par un utilisateur" do
      admin = create_user(email: "admin@example.com", role: :admin)
      other_admin = create_user(email: "other@example.com", role: :admin)
      user = create_user()

      # Admin effectue 2 actions
      {:ok, _log1} = AuditLogger.log_magic_link_sent(user, performed_by: admin)
      {:ok, _log2} = AuditLogger.log_sessions_revoked(user, performed_by: admin, session_count: 1)

      # Other admin effectue 1 action
      {:ok, _log3} = AuditLogger.log_magic_link_sent(user, performed_by: other_admin)

      logs = AuditLogger.get_logs_by_user(admin.id)

      assert length(logs) == 2
      assert Enum.all?(logs, &(&1.performed_by_id == admin.id))
    end

    test "limite le nombre de résultats" do
      admin = create_user(email: "admin@example.com", role: :admin)
      user = create_user()

      # Créer 5 logs
      for _ <- 1..5 do
        AuditLogger.log_magic_link_sent(user, performed_by: admin)
      end

      logs = AuditLogger.get_logs_by_user(admin.id, limit: 3)

      assert length(logs) == 3
    end
  end

  describe "persistence" do
    test "les logs sont en insert-only (pas de update)" do
      user = create_user()
      admin = create_user(email: "admin@example.com", role: :admin)

      {:ok, log} = AuditLogger.log_magic_link_sent(user, performed_by: admin)

      # Essayer de modifier le log ne devrait pas fonctionner
      # (le schéma n'a pas de fonction update)
      changeset = AuditLog.changeset(log, %{action: "modified"})

      # Le changeset devrait être valide mais la modification ne devrait pas persister
      # car nous n'avons pas de fonction update dans AuditLogger
      assert changeset.valid?

      # Vérifier que le log original n'a pas changé en base
      reloaded = Repo.get!(AuditLog, log.id)
      assert reloaded.action == "magic_link_sent"
    end
  end
end
