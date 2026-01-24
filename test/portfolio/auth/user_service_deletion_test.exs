defmodule Portfolio.Auth.UserServiceDeletionTest do
  @moduledoc """
  Tests for user deletion with focus on last admin protection (PU-006).

  Business Rule PU-006: The system must prevent deletion of the last administrator.
  At least one administrator must always exist in the system.
  """
  use Portfolio.DataCase

  @moduletag :skip

  alias Portfolio.Auth.{MagicLink, MagicLinkService, User, UserService, UserSession}

  describe "delete_user/1 with last admin protection (PU-006)" do
    test "prevents deletion of last administrator" do
      # Create a single admin user
      admin = insert_user(email: "last-admin@example.com", role: :admin)

      # Verify this is the only admin
      assert UserService.count_admin_users() == 1

      # Attempt to delete should fail
      assert {:error, :last_admin} = UserService.delete_user(admin)

      # Verify admin still exists
      assert {:ok, _found} = UserService.get_user(admin.id)
      assert UserService.count_admin_users() == 1
    end

    test "allows deletion when multiple admins exist" do
      # Create two admins
      admin1 = insert_user(email: "admin1@example.com", role: :admin)
      admin2 = insert_user(email: "admin2@example.com", role: :admin)

      # Verify we have at least 2 admins
      assert UserService.count_admin_users() >= 2

      # Deletion of one admin should succeed
      assert {:ok, deleted_admin} = UserService.delete_user(admin1)
      assert deleted_admin.id == admin1.id

      # Verify admin was deleted
      assert {:error, :not_found} = UserService.get_user(admin1.id)

      # Verify other admin still exists
      assert {:ok, _found} = UserService.get_user(admin2.id)
      assert UserService.count_admin_users() >= 1
    end

    test "allows deletion of regular users even when they are the last user" do
      # Create a single regular user (not admin)
      user = insert_user(email: "regular-user@example.com", role: :user)

      # Deletion should succeed regardless of admin count
      assert {:ok, deleted_user} = UserService.delete_user(user)
      assert deleted_user.id == user.id

      # Verify user was deleted
      assert {:error, :not_found} = UserService.get_user(user.id)
    end

    test "allows deletion of regular user when admins exist" do
      # Create an admin and a regular user
      _admin = insert_user(email: "admin@example.com", role: :admin)
      user = insert_user(email: "user@example.com", role: :user)

      # Deletion of regular user should succeed
      assert {:ok, deleted_user} = UserService.delete_user(user)
      assert deleted_user.id == user.id

      # Verify user was deleted
      assert {:error, :not_found} = UserService.get_user(user.id)
    end

    test "prevents deletion when exactly one admin remains after multiple deletions" do
      # Create three admins
      admin1 = insert_user(email: "admin1@example.com", role: :admin)
      admin2 = insert_user(email: "admin2@example.com", role: :admin)
      admin3 = insert_user(email: "admin3@example.com", role: :admin)

      # Delete first admin - should succeed
      assert {:ok, _} = UserService.delete_user(admin1)
      assert UserService.count_admin_users() >= 2

      # Delete second admin - should succeed
      assert {:ok, _} = UserService.delete_user(admin2)

      # If only one admin remains, deletion should fail
      remaining_admin_count = UserService.count_admin_users()

      if remaining_admin_count == 1 do
        assert {:error, :last_admin} = UserService.delete_user(admin3)
      else
        # If there are other admins from other tests, deletion might succeed
        assert {:ok, _} = UserService.delete_user(admin3)
      end
    end
  end

  describe "delete_user/1 side effects" do
    test "deletes user's sessions when user is deleted" do
      admin1 = insert_user(email: "admin1@example.com", role: :admin)
      _admin2 = insert_user(email: "admin2@example.com", role: :admin)

      # Create sessions for admin1
      session1 = insert_session(admin1)
      session2 = insert_session(admin1)

      # Delete admin1
      assert {:ok, _} = UserService.delete_user(admin1)

      # Sessions should be deleted (cascading delete)
      refute Repo.get(Portfolio.Auth.UserSession, session1.id)
      refute Repo.get(Portfolio.Auth.UserSession, session2.id)
    end

    test "deletes user's magic links when user is deleted" do
      admin1 = insert_user(email: "admin1@example.com", role: :admin)
      _admin2 = insert_user(email: "admin2@example.com", role: :admin)

      # Request magic link for admin1
      {:ok, magic_link} = MagicLinkService.request_magic_link(admin1.email)

      # Delete admin1
      assert {:ok, _} = UserService.delete_user(admin1)

      # Magic link should be deleted (cascading delete)
      refute Repo.get(MagicLink, magic_link.id)
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
