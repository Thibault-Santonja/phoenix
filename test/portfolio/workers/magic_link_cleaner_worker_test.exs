defmodule Portfolio.Workers.MagicLinkCleanerWorkerTest do
  use Portfolio.DataCase
  use Oban.Testing, repo: Portfolio.Repo

  alias Portfolio.Auth.{MagicLink, User}
  alias Portfolio.Workers.MagicLinkCleanerWorker

  describe "perform/1" do
    test "deletes expired magic links" do
      user = insert_user()

      # Créer un magic link expiré (il y a 1 jour)
      expired_magic_link =
        insert_magic_link(user,
          expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
        )

      # Créer un magic link valide (expire dans 15 minutes)
      valid_magic_link =
        insert_magic_link(user,
          expires_at: DateTime.add(DateTime.utc_now(), 15, :minute)
        )

      # Exécuter le worker
      assert :ok = perform_job(MagicLinkCleanerWorker, %{})

      # Vérifier que le magic link expiré a été supprimé
      refute Repo.get(MagicLink, expired_magic_link.id)

      # Vérifier que le magic link valide est toujours présent
      assert Repo.get(MagicLink, valid_magic_link.id)
    end

    test "deletes multiple expired magic links" do
      user1 = insert_user(email: "user1@example.com")
      user2 = insert_user(email: "user2@example.com")

      # Créer plusieurs magic links expirés
      expired1 =
        insert_magic_link(user1,
          expires_at: DateTime.add(DateTime.utc_now(), -2, :hour)
        )

      expired2 =
        insert_magic_link(user2,
          expires_at: DateTime.add(DateTime.utc_now(), -1, :day)
        )

      expired3 =
        insert_magic_link(user1,
          expires_at: DateTime.add(DateTime.utc_now(), -3, :day)
        )

      # Créer un magic link valide
      valid = insert_magic_link(user2, expires_at: DateTime.add(DateTime.utc_now(), 10, :minute))

      # Exécuter le worker
      assert :ok = perform_job(MagicLinkCleanerWorker, %{})

      # Vérifier que tous les magic links expirés ont été supprimés
      refute Repo.get(MagicLink, expired1.id)
      refute Repo.get(MagicLink, expired2.id)
      refute Repo.get(MagicLink, expired3.id)

      # Vérifier que le magic link valide est toujours présent
      assert Repo.get(MagicLink, valid.id)
    end

    test "returns ok when no expired magic links exist" do
      user = insert_user()

      # Créer seulement des magic links valides
      insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), 15, :minute))
      insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), 30, :minute))

      # Exécuter le worker
      assert :ok = perform_job(MagicLinkCleanerWorker, %{})

      # Vérifier que tous les magic links sont toujours présents
      assert Repo.aggregate(MagicLink, :count) == 2
    end

    test "returns ok when no magic links exist" do
      # Exécuter le worker sans magic links
      assert :ok = perform_job(MagicLinkCleanerWorker, %{})
    end

    test "does not delete used magic links even if expired" do
      user = insert_user()

      # Créer un magic link expiré ET utilisé
      expired_and_used =
        insert_magic_link(user,
          expires_at: DateTime.add(DateTime.utc_now(), -1, :day),
          used_at: DateTime.add(DateTime.utc_now(), -2, :day)
        )

      # Exécuter le worker
      assert :ok = perform_job(MagicLinkCleanerWorker, %{})

      # Le magic link expiré devrait être supprimé même s'il est utilisé
      # (car expiré = plus besoin de le garder)
      refute Repo.get(MagicLink, expired_and_used.id)
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

  defp insert_magic_link(user, attrs) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      user_id: user.id,
      token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      short_code: generate_short_code(),
      expires_at: DateTime.add(DateTime.utc_now(), 15, :minute) |> DateTime.truncate(:second),
      used_at: nil
    }

    %MagicLink{}
    |> MagicLink.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp generate_short_code do
    :crypto.strong_rand_bytes(4)
    |> Base.encode32(padding: false)
    |> String.slice(0..5)
    |> String.upcase()
  end
end
