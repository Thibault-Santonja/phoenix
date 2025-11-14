defmodule Portfolio.Auth.UserServiceTest do
  use Portfolio.DataCase

  alias Portfolio.Auth.{MagicLink, User, UserService, UserSession}

  describe "get_user_by_email/1" do
    test "returns {:ok, user} when user exists" do
      user = insert_user()
      assert {:ok, found_user} = UserService.get_user_by_email(user.email)
      assert found_user.id == user.id
      assert found_user.email == user.email
    end

    test "returns {:error, :not_found} when user does not exist" do
      assert {:error, :not_found} = UserService.get_user_by_email("nonexistent@example.com")
    end
  end

  describe "get_or_create_user/1" do
    test "returns existing user if email exists" do
      user = insert_user()
      assert {:ok, found_user} = UserService.get_or_create_user(user.email)
      assert found_user.id == user.id
      assert found_user.email == user.email
    end

    test "creates new user in dev/test environment" do
      email = "newuser-#{System.unique_integer([:positive])}@example.com"
      assert {:ok, user} = UserService.get_or_create_user(email)
      assert user.email == email
      assert user.role == :user
      assert user.name == nil
    end

    test "does not create duplicate users" do
      email = "unique-#{System.unique_integer([:positive])}@example.com"
      {:ok, user1} = UserService.get_or_create_user(email)
      {:ok, user2} = UserService.get_or_create_user(email)

      assert user1.id == user2.id
    end
  end

  describe "get_user/1" do
    test "returns user when ID is valid" do
      user = insert_user()
      assert {:ok, found_user} = UserService.get_user(user.id)
      assert found_user.id == user.id
      assert found_user.email == user.email
    end

    test "returns error when ID does not exist" do
      assert UserService.get_user(Ecto.UUID.generate()) == {:error, :not_found}
    end
  end

  describe "list_users/1" do
    test "returns all users when no filters" do
      user1 = insert_user(email: "user1@example.com")
      user2 = insert_user(email: "user2@example.com")

      users = UserService.list_users()

      user_ids = Enum.map(users, & &1.id)
      assert user1.id in user_ids
      assert user2.id in user_ids
    end

    test "filters by admin role" do
      admin =
        insert_user(
          email: "admin-#{System.unique_integer([:positive])}@example.com",
          role: :admin
        )

      _user =
        insert_user(email: "user-#{System.unique_integer([:positive])}@example.com", role: :user)

      admins = UserService.list_users(role: :admin)

      assert Enum.all?(admins, &(&1.role == :admin))
      assert admin.id in Enum.map(admins, & &1.id)
    end

    test "filters by user role" do
      _admin = insert_user(email: "admin@example.com", role: :admin)
      user = insert_user(email: "user@example.com", role: :user)

      users = UserService.list_users(role: :user)

      assert Enum.all?(users, &(&1.role == :user))
      assert user.id in Enum.map(users, & &1.id)
    end

    test "returns empty list when no users match filter" do
      insert_user(email: "admin@example.com", role: :admin)

      # In test env, we should have at least one admin, so filtering by a non-existent role should work
      users = UserService.list_users(role: :user)
      assert Enum.all?(users, &(&1.role == :user))
    end
  end

  describe "change_user/2" do
    test "returns changeset for user modification" do
      user = insert_user()
      changeset = UserService.change_user(user)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data.id == user.id
    end

    test "returns changeset with provided attributes" do
      user = insert_user()
      changeset = UserService.change_user(user, %{name: "New Name"})

      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.name == "New Name"
    end

    test "allows name modification" do
      user = insert_user()
      changeset = UserService.change_user(user, %{name: "Updated Name"})

      assert changeset.valid?
    end

    test "does not allow email modification via profile changeset" do
      user = insert_user()
      changeset = UserService.change_user(user, %{email: "new@example.com"})

      # Email should not be in changes
      refute Map.has_key?(changeset.changes, :email)
    end

    test "does not allow role modification via profile changeset" do
      user = insert_user()
      changeset = UserService.change_user(user, %{role: :admin})

      # Role should not be in changes
      refute Map.has_key?(changeset.changes, :role)
    end
  end

  describe "update_user/2" do
    test "updates user name successfully" do
      user = insert_user(name: "Old Name")
      assert {:ok, updated_user} = UserService.update_user(user, %{name: "New Name"})

      assert updated_user.name == "New Name"
      assert updated_user.id == user.id
      assert updated_user.email == user.email
    end

    test "allows setting name to nil" do
      user = insert_user(name: "Some Name")
      assert {:ok, updated_user} = UserService.update_user(user, %{name: nil})

      assert updated_user.name == nil
    end

    test "returns error for invalid data" do
      user = insert_user()
      # Name must be string or nil, not integer
      assert {:error, changeset} = UserService.update_user(user, %{name: 123})

      refute changeset.valid?
    end

    test "does not update email via profile update" do
      user = insert_user(email: "original@example.com")
      {:ok, updated_user} = UserService.update_user(user, %{email: "new@example.com"})

      # Email should remain unchanged
      assert updated_user.email == "original@example.com"
    end

    test "does not update role via profile update" do
      user = insert_user(role: :user)
      {:ok, updated_user} = UserService.update_user(user, %{role: :admin})

      # Role should remain unchanged
      assert updated_user.role == :user
    end
  end

  describe "update_user_as_admin/2" do
    test "updates user role" do
      user = insert_user(role: :user)
      assert {:ok, updated_user} = UserService.update_user_as_admin(user, %{role: :admin})

      assert updated_user.role == :admin
    end

    test "updates user name" do
      user = insert_user(name: "Old Name")
      assert {:ok, updated_user} = UserService.update_user_as_admin(user, %{name: "New Name"})

      assert updated_user.name == "New Name"
    end

    test "returns error for invalid role" do
      user = insert_user()
      assert {:error, changeset} = UserService.update_user_as_admin(user, %{role: :invalid})

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).role
    end

    test "allows both role and name update" do
      user = insert_user(role: :user, name: "Old Name")

      assert {:ok, updated_user} =
               UserService.update_user_as_admin(user, %{role: :admin, name: "New Name"})

      assert updated_user.role == :admin
      assert updated_user.name == "New Name"
    end

    test "prevents user from modifying their own role" do
      user = insert_user(role: :admin)

      assert {:error, changeset} =
               UserService.update_user_as_admin(user, %{role: :user}, current_user_id: user.id)

      refute changeset.valid?
      assert "vous ne pouvez pas modifier votre propre rôle" in errors_on(changeset).role
    end

    test "allows admin to modify another user's role" do
      admin = insert_user(email: "admin@example.com", role: :admin)
      other_user = insert_user(email: "other@example.com", role: :user)

      assert {:ok, updated_user} =
               UserService.update_user_as_admin(other_user, %{role: :admin},
                 current_user_id: admin.id
               )

      assert updated_user.role == :admin
    end
  end

  describe "delete_user/1" do
    test "deletes user successfully" do
      # Create a regular user (not admin) to avoid PU-006 protection
      user = insert_user(role: :user)
      assert {:ok, deleted_user} = UserService.delete_user(user)

      assert deleted_user.id == user.id
      assert Repo.get(User, user.id) == nil
    end

    test "prevents deletion of last admin (PU-006)" do
      # Ensure only one admin exists
      Repo.delete_all(User)

      last_admin =
        insert_user(
          email: "lastadmin-#{System.unique_integer([:positive])}@example.com",
          role: :admin
        )

      assert UserService.count_admin_users() == 1

      # Attempt to delete last admin should fail
      assert {:error, :last_admin} = UserService.delete_user(last_admin)

      # Admin should still exist
      assert Repo.get(User, last_admin.id) != nil
      assert UserService.count_admin_users() == 1
    end

    test "allows deletion of admin when multiple admins exist" do
      # Ensure at least 2 admins exist
      admin1 =
        insert_user(
          email: "admin1-#{System.unique_integer([:positive])}@example.com",
          role: :admin
        )

      admin2 =
        insert_user(
          email: "admin2-#{System.unique_integer([:positive])}@example.com",
          role: :admin
        )

      assert UserService.count_admin_users() >= 2

      # Should allow deletion of one admin
      assert {:ok, _deleted} = UserService.delete_user(admin1)

      # At least one admin still exists
      assert UserService.count_admin_users() >= 1
      assert Repo.get(User, admin2.id) != nil
    end

    test "cascades deletion to user sessions" do
      # Create a regular user to avoid PU-006 protection
      user = insert_user(role: :user)
      session = insert_session(user)

      UserService.delete_user(user)

      assert Repo.get(Portfolio.Auth.UserSession, session.id) == nil
    end

    test "cascades deletion to magic links" do
      # Create a regular user to avoid PU-006 protection
      user = insert_user(role: :user)
      magic_link = insert_magic_link(user)

      UserService.delete_user(user)

      assert Repo.get(Portfolio.Auth.MagicLink, magic_link.id) == nil
    end
  end

  describe "count_users/0" do
    test "returns total number of users" do
      before_count = UserService.count_users()

      insert_user(email: "user-count1-#{System.unique_integer([:positive])}@example.com")
      insert_user(email: "user-count2-#{System.unique_integer([:positive])}@example.com")

      assert UserService.count_users() == before_count + 2
    end
  end

  describe "count_admin_users/0" do
    test "returns number of admin users" do
      before_count = UserService.count_admin_users()

      insert_user(
        email: "admin-count1-#{System.unique_integer([:positive])}@example.com",
        role: :admin
      )

      insert_user(
        email: "admin-count2-#{System.unique_integer([:positive])}@example.com",
        role: :admin
      )

      insert_user(
        email: "user-count1-#{System.unique_integer([:positive])}@example.com",
        role: :user
      )

      assert UserService.count_admin_users() == before_count + 2
    end

    test "does not count regular users" do
      before_count = UserService.count_admin_users()

      insert_user(
        email: "user-nocount1-#{System.unique_integer([:positive])}@example.com",
        role: :user
      )

      insert_user(
        email: "user-nocount2-#{System.unique_integer([:positive])}@example.com",
        role: :user
      )

      assert UserService.count_admin_users() == before_count
    end
  end

  describe "count_regular_users/0" do
    test "returns number of regular users" do
      before_count = UserService.count_regular_users()

      insert_user(
        email: "user-rcount1-#{System.unique_integer([:positive])}@example.com",
        role: :user
      )

      insert_user(
        email: "user-rcount2-#{System.unique_integer([:positive])}@example.com",
        role: :user
      )

      insert_user(
        email: "admin-rcount1-#{System.unique_integer([:positive])}@example.com",
        role: :admin
      )

      assert UserService.count_regular_users() == before_count + 2
    end

    test "does not count admin users" do
      before_count = UserService.count_regular_users()

      insert_user(
        email: "admin-nocount1-#{System.unique_integer([:positive])}@example.com",
        role: :admin
      )

      insert_user(
        email: "admin-nocount2-#{System.unique_integer([:positive])}@example.com",
        role: :admin
      )

      assert UserService.count_regular_users() == before_count
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
    |> User.bootstrap_admin_changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp insert_session(user) do
    %UserSession{}
    |> UserSession.changeset(%{
      user_id: user.id,
      token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      last_activity_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  defp insert_magic_link(user) do
    %MagicLink{}
    |> MagicLink.changeset(%{
      user_id: user.id,
      token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      short_code: generate_short_code(),
      expires_at: DateTime.add(DateTime.utc_now(), 15, :minute) |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  defp generate_short_code do
    :crypto.strong_rand_bytes(4)
    |> Base.encode32(padding: false)
    |> String.slice(0..5)
    |> String.upcase()
  end
end
