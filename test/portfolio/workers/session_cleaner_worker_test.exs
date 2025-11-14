defmodule Portfolio.Workers.SessionCleanerWorkerTest do
  use Portfolio.DataCase
  use Oban.Testing, repo: Portfolio.Repo

  alias Portfolio.Auth.{User, UserSession}
  alias Portfolio.Workers.SessionCleanerWorker

  describe "perform/1" do
    test "deletes expired sessions based on inactivity" do
      user = insert_user()

      # Créer une session expirée (dernière activité il y a 3 heures, expiration = 2h par défaut)
      expired_session =
        insert_session(user,
          last_activity_at: DateTime.add(DateTime.utc_now(), -3, :hour)
        )

      # Créer une session valide (dernière activité il y a 1 heure)
      valid_session =
        insert_session(user,
          last_activity_at: DateTime.add(DateTime.utc_now(), -1, :hour)
        )

      # Exécuter le worker
      assert :ok = perform_job(SessionCleanerWorker, %{})

      # Vérifier que la session expirée a été supprimée
      refute Repo.get(UserSession, expired_session.id)

      # Vérifier que la session valide est toujours présente
      assert Repo.get(UserSession, valid_session.id)
    end

    test "deletes multiple expired sessions" do
      user1 = insert_user(email: "user1@example.com")
      user2 = insert_user(email: "user2@example.com")

      # Créer plusieurs sessions expirées
      expired1 =
        insert_session(user1,
          last_activity_at: DateTime.add(DateTime.utc_now(), -5, :hour)
        )

      expired2 =
        insert_session(user2,
          last_activity_at: DateTime.add(DateTime.utc_now(), -10, :hour)
        )

      expired3 =
        insert_session(user1,
          last_activity_at: DateTime.add(DateTime.utc_now(), -24, :hour)
        )

      # Créer des sessions valides
      valid1 =
        insert_session(user1,
          last_activity_at: DateTime.add(DateTime.utc_now(), -30, :minute)
        )

      valid2 = insert_session(user2, last_activity_at: DateTime.utc_now())

      # Exécuter le worker
      assert :ok = perform_job(SessionCleanerWorker, %{})

      # Vérifier que toutes les sessions expirées ont été supprimées
      refute Repo.get(UserSession, expired1.id)
      refute Repo.get(UserSession, expired2.id)
      refute Repo.get(UserSession, expired3.id)

      # Vérifier que les sessions valides sont toujours présentes
      assert Repo.get(UserSession, valid1.id)
      assert Repo.get(UserSession, valid2.id)
    end

    test "returns ok when no expired sessions exist" do
      user = insert_user()

      # Créer seulement des sessions valides
      insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -30, :minute))
      insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -1, :hour))

      # Exécuter le worker
      assert :ok = perform_job(SessionCleanerWorker, %{})

      # Vérifier que toutes les sessions sont toujours présentes
      assert Repo.aggregate(UserSession, :count) == 2
    end

    test "returns ok when no sessions exist" do
      # Exécuter le worker sans sessions
      assert :ok = perform_job(SessionCleanerWorker, %{})
    end

    test "respects session expiration configuration" do
      user = insert_user()

      # Session clairement expirée (3 heures d'inactivité, limite = 2h)
      expired_session =
        insert_session(user,
          last_activity_at: DateTime.add(DateTime.utc_now(), -3, :hour)
        )

      # Session clairement valide (1 heure d'inactivité)
      valid_session =
        insert_session(user,
          last_activity_at: DateTime.add(DateTime.utc_now(), -1, :hour)
        )

      # Exécuter le worker
      assert :ok = perform_job(SessionCleanerWorker, %{})

      # La session expirée devrait être supprimée
      refute Repo.get(UserSession, expired_session.id)

      # La session valide devrait être conservée
      assert Repo.get(UserSession, valid_session.id)
    end
  end

  # Helper functions
  defp insert_user(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      email: "test-#{System.unique_integer([:positive])}@example.com",
      role: :admin
    }

    %User{}
    |> User.registration_changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp insert_session(user, attrs) do
    attrs = Enum.into(attrs, %{})

    # Générer un token en clair
    raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    default_attrs = %{
      user_id: user.id,
      token: raw_token,
      last_activity_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    session =
      %UserSession{}
      |> UserSession.changeset(Map.merge(default_attrs, attrs))
      |> Repo.insert!()

    # Retourner la session avec le token en clair (pas le hash)
    %{session | token: raw_token}
  end
end
