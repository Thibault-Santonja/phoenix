defmodule Portfolio.Auth.UserServiceRoleTest do
  @moduledoc """
  Tests for role modification protection in UserService.

  Ensures that administrators cannot modify their own role,
  and that session caches are properly invalidated when roles change.
  """
  use Portfolio.DataCase

  @moduletag :skip

  alias Portfolio.Auth.{User, UserService, UserSession}

  describe "update_user_as_admin/3 role modification protection" do
    test "prevents admin from modifying their own role" do
      admin = insert_user(email: "admin@example.com", role: :admin)

      # Admin tries to change their own role to :user
      result =
        UserService.update_user_as_admin(
          admin,
          %{role: :user},
          current_user_id: admin.id
        )

      assert {:error, changeset} = result
      assert "you cannot modify your own role" in errors_on(changeset).role
    end

    test "allows admin to modify another user's role" do
      admin = insert_user(email: "admin@example.com", role: :admin)
      user = insert_user(email: "user@example.com", role: :user)

      # Admin changes another user's role
      result =
        UserService.update_user_as_admin(
          user,
          %{role: :admin},
          current_user_id: admin.id
        )

      assert {:ok, updated_user} = result
      assert updated_user.role == :admin
      assert updated_user.id == user.id
    end

    test "allows admin to modify another admin's role" do
      admin1 = insert_user(email: "admin1@example.com", role: :admin)
      admin2 = insert_user(email: "admin2@example.com", role: :admin)
      _admin3 = insert_user(email: "admin3@example.com", role: :admin)

      # Admin1 demotes admin2 to regular user
      result =
        UserService.update_user_as_admin(
          admin2,
          %{role: :user},
          current_user_id: admin1.id
        )

      assert {:ok, updated_user} = result
      assert updated_user.role == :user
      assert updated_user.id == admin2.id
    end

    test "rejects invalid role values" do
      admin = insert_user(email: "admin@example.com", role: :admin)
      user = insert_user(email: "user@example.com", role: :user)

      # Try to set invalid role
      result =
        UserService.update_user_as_admin(
          user,
          %{role: :invalid_role},
          current_user_id: admin.id
        )

      assert {:error, changeset} = result
      assert "is invalid" in errors_on(changeset).role
    end

    test "allows role modification when current_user_id is not provided" do
      user = insert_user(email: "user@example.com", role: :user)

      # Without current_user_id (e.g., system operation), role change allowed
      result = UserService.update_user_as_admin(user, %{role: :admin})

      assert {:ok, updated_user} = result
      assert updated_user.role == :admin
    end

    test "allows admin to promote user to admin" do
      admin = insert_user(email: "admin@example.com", role: :admin)
      user = insert_user(email: "user@example.com", role: :user)

      result =
        UserService.update_user_as_admin(
          user,
          %{role: :admin},
          current_user_id: admin.id
        )

      assert {:ok, updated_user} = result
      assert updated_user.role == :admin
    end

    test "allows admin to demote another admin to user" do
      admin1 = insert_user(email: "admin1@example.com", role: :admin)
      admin2 = insert_user(email: "admin2@example.com", role: :admin)
      _admin3 = insert_user(email: "admin3@example.com", role: :admin)

      result =
        UserService.update_user_as_admin(
          admin2,
          %{role: :user},
          current_user_id: admin1.id
        )

      assert {:ok, updated_user} = result
      assert updated_user.role == :user
    end
  end

  describe "update_user_as_admin/3 session cache invalidation" do
    test "invalidates all user session caches when role changes" do
      admin = insert_user(email: "admin@example.com", role: :admin)
      user = insert_user(email: "user@example.com", role: :user)

      # Create sessions for the user
      session1 = insert_session(user)
      session2 = insert_session(user)

      # Populate cache for both sessions
      cache_key1 = {:session, session1.token}
      cache_key2 = {:session, session2.token}
      Cachex.put(:portfolio_cache, cache_key1, %{user_id: user.id, role: :user})
      Cachex.put(:portfolio_cache, cache_key2, %{user_id: user.id, role: :user})

      # Verify cache is populated
      assert {:ok, _} = Cachex.get(:portfolio_cache, cache_key1)
      assert {:ok, _} = Cachex.get(:portfolio_cache, cache_key2)

      # Change user's role
      {:ok, _updated_user} =
        UserService.update_user_as_admin(
          user,
          %{role: :admin},
          current_user_id: admin.id
        )

      # Verify cache was cleared for both sessions
      assert {:ok, nil} = Cachex.get(:portfolio_cache, cache_key1)
      assert {:ok, nil} = Cachex.get(:portfolio_cache, cache_key2)
    end

    test "does not invalidate caches when role does not change" do
      admin = insert_user(email: "admin@example.com", role: :admin)
      user = insert_user(email: "user@example.com", role: :user)

      # Create session for the user
      session = insert_session(user)

      # Populate cache
      cache_key = {:session, session.token}
      Cachex.put(:portfolio_cache, cache_key, %{user_id: user.id, role: :user})

      # Verify cache is populated
      assert {:ok, _} = Cachex.get(:portfolio_cache, cache_key)

      # Update user without changing role
      {:ok, _updated_user} =
        UserService.update_user_as_admin(
          user,
          %{name: "New Name"},
          current_user_id: admin.id
        )

      # Cache should still be present
      assert {:ok, cached_value} = Cachex.get(:portfolio_cache, cache_key)
      assert cached_value != nil
    end

    test "invalidates caches only for the modified user, not other users" do
      admin = insert_user(email: "admin@example.com", role: :admin)
      user1 = insert_user(email: "user1@example.com", role: :user)
      user2 = insert_user(email: "user2@example.com", role: :user)

      # Create sessions
      session1 = insert_session(user1)
      session2 = insert_session(user2)

      # Populate caches
      cache_key1 = {:session, session1.token}
      cache_key2 = {:session, session2.token}
      Cachex.put(:portfolio_cache, cache_key1, %{user_id: user1.id})
      Cachex.put(:portfolio_cache, cache_key2, %{user_id: user2.id})

      # Change user1's role
      {:ok, _updated_user} =
        UserService.update_user_as_admin(
          user1,
          %{role: :admin},
          current_user_id: admin.id
        )

      # user1's cache should be cleared
      assert {:ok, nil} = Cachex.get(:portfolio_cache, cache_key1)

      # user2's cache should still be present
      assert {:ok, cached_value} = Cachex.get(:portfolio_cache, cache_key2)
      assert cached_value != nil
    end
  end

  # Helper functions
  defp insert_user(attrs) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      email: "test-#{System.unique_integer([:positive])}@example.com",
      role: :admin
    }

    %User{}
    |> User.bootstrap_admin_changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp insert_session(user) do
    %UserSession{}
    |> UserSession.changeset(%{
      user_id: user.id,
      token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      user_agent: "Test User Agent",
      ip_address: "127.0.0.1"
    })
    |> Repo.insert!()
  end
end
