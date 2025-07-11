defmodule Portfolio.AuthTest do
  use Portfolio.DataCase

  alias Portfolio.Auth
  alias Portfolio.Auth.{User, MagicLink, UserSession}

  describe "get_user_by_email/1" do
    test "returns {:ok, user} when user exists" do
      user = insert_user()
      assert {:ok, found_user} = Auth.get_user_by_email(user.email)
      assert found_user.id == user.id
    end

    test "returns {:error, :not_found} when user does not exist" do
      assert {:error, :not_found} = Auth.get_user_by_email("nonexistent@example.com")
    end
  end

  describe "get_or_create_user/1" do
    test "returns existing user if email exists" do
      user = insert_user()
      assert {:ok, found_user} = Auth.get_or_create_user(user.email)
      assert found_user.id == user.id
    end

    test "creates new user in dev environment" do
      email = "newuser@example.com"
      assert {:ok, user} = Auth.get_or_create_user(email)
      assert user.email == email
      assert user.role == "admin"
    end
  end

  describe "get_user/1" do
    test "returns user when ID is valid" do
      user = insert_user()
      found_user = Auth.get_user(user.id)
      assert found_user.id == user.id
    end

    test "returns nil when ID does not exist" do
      assert Auth.get_user(Ecto.UUID.generate()) == nil
    end
  end

  describe "request_magic_link/1" do
    test "creates magic link for existing user" do
      user = insert_user()
      assert {:ok, magic_link} = Auth.request_magic_link(user.email)

      assert magic_link.user_id == user.id
      assert magic_link.token != nil
      assert magic_link.expires_at != nil
      assert magic_link.used_at == nil
    end

    test "creates user and magic link for new email in dev" do
      email = "newuser@example.com"
      assert {:ok, magic_link} = Auth.request_magic_link(email)

      assert magic_link.user_id != nil
      assert magic_link.token != nil
    end

    test "magic link expires in 15 minutes" do
      user = insert_user()
      assert {:ok, magic_link} = Auth.request_magic_link(user.email)

      expected_expiry = DateTime.add(DateTime.utc_now(), 15, :minute)
      diff = DateTime.diff(magic_link.expires_at, expected_expiry, :second)

      # Allow 2 seconds tolerance
      assert abs(diff) <= 2
    end
  end

  describe "verify_magic_link/1" do
    test "returns {:ok, user} for valid magic link" do
      user = insert_user()
      {:ok, magic_link} = Auth.request_magic_link(user.email)

      assert {:ok, verified_user} = Auth.verify_magic_link(magic_link.token)
      assert verified_user.id == user.id
    end

    test "marks magic link as used after verification" do
      user = insert_user()
      {:ok, magic_link} = Auth.request_magic_link(user.email)

      Auth.verify_magic_link(magic_link.token)

      used_magic_link = Repo.get(MagicLink, magic_link.id)
      assert used_magic_link.used_at != nil
    end

    test "returns {:error, :already_used} for used magic link" do
      user = insert_user()
      {:ok, magic_link} = Auth.request_magic_link(user.email)

      {:ok, _user} = Auth.verify_magic_link(magic_link.token)
      assert {:error, :already_used} = Auth.verify_magic_link(magic_link.token)
    end

    test "returns {:error, :expired} for expired magic link" do
      user = insert_user()

      magic_link =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), -1, :hour))

      assert {:error, :expired} = Auth.verify_magic_link(magic_link.token)
    end

    test "returns {:error, :invalid_token} for non-existent token" do
      assert {:error, :invalid_token} = Auth.verify_magic_link("invalid-token")
    end
  end

  describe "delete_expired_magic_links/0" do
    test "deletes magic links that have expired" do
      user = insert_user()

      expired_link =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), -1, :hour))

      valid_link =
        insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), 15, :minute))

      {count, nil} = Auth.delete_expired_magic_links()

      assert count == 1
      assert Repo.get(MagicLink, expired_link.id) == nil
      assert Repo.get(MagicLink, valid_link.id) != nil
    end

    test "returns {0, nil} when no expired links" do
      user = insert_user()
      insert_magic_link(user, expires_at: DateTime.add(DateTime.utc_now(), 15, :minute))

      assert {0, nil} = Auth.delete_expired_magic_links()
    end
  end

  describe "create_session/1" do
    test "creates session with token" do
      user = insert_user()
      assert {:ok, session} = Auth.create_session(user)

      assert session.user_id == user.id
      assert session.token != nil
      assert session.last_activity_at != nil
    end

    test "generates unique tokens" do
      user = insert_user()
      {:ok, session1} = Auth.create_session(user)
      {:ok, session2} = Auth.create_session(user)

      assert session1.token != session2.token
    end
  end

  describe "get_session_by_token/1" do
    test "returns session for valid token" do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      found_session = Auth.get_session_by_token(session.token)
      assert found_session.id == session.id
      assert found_session.user.id == user.id
    end

    test "returns nil for invalid token" do
      assert Auth.get_session_by_token("invalid-token") == nil
    end

    test "returns nil and deletes expired session" do
      user = insert_user()

      session =
        insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -2, :hour))

      assert Auth.get_session_by_token(session.token) == nil
      assert Repo.get(UserSession, session.id) == nil
    end
  end

  describe "update_session_activity/1" do
    test "updates last_activity_at" do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      # Wait a bit
      :timer.sleep(1000)

      {:ok, updated_session} = Auth.update_session_activity(session)

      assert DateTime.compare(updated_session.last_activity_at, session.last_activity_at) == :gt
    end
  end

  describe "delete_session/1" do
    test "deletes session" do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      assert {:ok, _deleted} = Auth.delete_session(session)
      assert Repo.get(UserSession, session.id) == nil
    end
  end

  describe "delete_all_user_sessions/1" do
    test "deletes all sessions for a user" do
      user = insert_user()
      {:ok, session1} = Auth.create_session(user)
      {:ok, session2} = Auth.create_session(user)

      {count, nil} = Auth.delete_all_user_sessions(user)

      assert count == 2
      assert Repo.get(UserSession, session1.id) == nil
      assert Repo.get(UserSession, session2.id) == nil
    end

    test "does not delete sessions from other users" do
      user1 = insert_user()
      user2 = insert_user(email: "user2@example.com")
      {:ok, session1} = Auth.create_session(user1)
      {:ok, session2} = Auth.create_session(user2)

      Auth.delete_all_user_sessions(user1)

      assert Repo.get(UserSession, session1.id) == nil
      assert Repo.get(UserSession, session2.id) != nil
    end
  end

  describe "delete_expired_sessions/0" do
    test "deletes sessions expired due to inactivity" do
      user = insert_user()

      expired_session =
        insert_session(user, last_activity_at: DateTime.add(DateTime.utc_now(), -2, :hour))

      valid_session = insert_session(user, last_activity_at: DateTime.utc_now())

      {count, nil} = Auth.delete_expired_sessions()

      assert count == 1
      assert Repo.get(UserSession, expired_session.id) == nil
      assert Repo.get(UserSession, valid_session.id) != nil
    end
  end

  # Helper functions
  defp insert_user(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      email: "test@example.com",
      role: "admin"
    }

    %User{}
    |> User.registration_changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp insert_magic_link(user, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      user_id: user.id,
      token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      expires_at: DateTime.add(DateTime.utc_now(), 15, :minute) |> DateTime.truncate(:second)
    }

    %MagicLink{}
    |> MagicLink.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp insert_session(user, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      user_id: user.id,
      token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      last_activity_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %UserSession{}
    |> UserSession.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end
end
