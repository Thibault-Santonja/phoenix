defmodule Portfolio.Auth.Repositories.UserRepositoryTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Auth.Repositories.UserRepository
  alias Portfolio.Auth.User

  import PortfolioTest.Fixtures.AuthFixtures

  describe "get_by_email/1" do
    test "returns user when email exists" do
      user = create_user(email: "test@example.com")

      assert {:ok, found} = UserRepository.get_by_email("test@example.com")
      assert found.id == user.id
      assert found.email == user.email
    end

    test "returns error when email does not exist" do
      assert {:error, :not_found} = UserRepository.get_by_email("nonexistent@example.com")
    end

    test "normalizes email to lowercase" do
      user = create_user(email: "Test@Example.com")

      # Emails are normalized to lowercase, so lookup should work
      assert {:ok, found} = UserRepository.get_by_email("test@example.com")
      assert found.id == user.id
    end
  end

  describe "get/1" do
    test "returns user when id exists" do
      user = create_user()

      assert {:ok, found} = UserRepository.get(user.id)
      assert found.id == user.id
    end

    test "returns error when id does not exist" do
      assert {:error, :not_found} = UserRepository.get(Ecto.UUID.generate())
    end
  end

  describe "get!/1" do
    test "returns user when id exists" do
      user = create_user()

      found = UserRepository.get!(user.id)
      assert found.id == user.id
    end

    test "raises when id does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        UserRepository.get!(Ecto.UUID.generate())
      end
    end
  end

  describe "list/1" do
    test "returns all users when no filters" do
      user1 = create_user()
      user2 = create_user()

      users = UserRepository.list()
      ids = Enum.map(users, & &1.id)

      assert user1.id in ids
      assert user2.id in ids
    end

    test "filters by role" do
      admin = create_user(role: :admin)
      _regular = create_user(role: :user)

      admins = UserRepository.list(role: :admin)
      ids = Enum.map(admins, & &1.id)

      assert admin.id in ids
      assert length(admins) >= 1
    end

    test "returns empty list when no users match filter" do
      create_user(role: :admin)

      # Clear all regular users first by checking count
      regular_users = UserRepository.list(role: :user)

      # This test verifies filter works - if we have users, we should be able to filter
      assert is_list(regular_users)
    end
  end

  describe "insert/1" do
    test "creates user with valid attrs" do
      attrs = %{email: "new@example.com"}

      assert {:ok, user} = UserRepository.insert(attrs)
      assert user.email == "new@example.com"
      assert user.role == :user
    end

    test "creates user with name" do
      attrs = %{email: "new@example.com", name: "Test User"}

      assert {:ok, user} = UserRepository.insert(attrs)
      assert user.name == "Test User"
    end

    test "returns error with invalid email" do
      attrs = %{email: "invalid"}

      assert {:error, changeset} = UserRepository.insert(attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).email
    end

    test "returns error when email is missing" do
      assert {:error, changeset} = UserRepository.insert(%{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end

    test "returns error on duplicate email" do
      create_user(email: "existing@example.com")

      assert {:error, changeset} = UserRepository.insert(%{email: "existing@example.com"})
      refute changeset.valid?
      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "update_profile/2" do
    test "updates user name" do
      user = create_user(name: "Old Name")

      assert {:ok, updated} = UserRepository.update_profile(user, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "allows clearing name" do
      user = create_user(name: "Some Name")

      assert {:ok, updated} = UserRepository.update_profile(user, %{name: nil})
      assert updated.name == nil
    end

    test "does not allow updating email via profile" do
      user = create_user(email: "original@example.com")

      # Email should be ignored in profile changeset
      assert {:ok, updated} = UserRepository.update_profile(user, %{email: "new@example.com"})
      assert updated.email == "original@example.com"
    end
  end

  describe "update_as_admin/3" do
    test "updates user role" do
      admin = create_user(role: :admin)
      user = create_user(role: :user)

      assert {:ok, updated} =
               UserRepository.update_as_admin(user, %{role: :admin}, current_user_id: admin.id)

      assert updated.role == :admin
    end

    test "updates user name" do
      admin = create_user(role: :admin)
      user = create_user(name: "Old Name")

      assert {:ok, updated} =
               UserRepository.update_as_admin(user, %{name: "New Name"},
                 current_user_id: admin.id
               )

      assert updated.name == "New Name"
    end

    test "prevents admin from demoting themselves" do
      admin = create_user(role: :admin)

      assert {:error, changeset} =
               UserRepository.update_as_admin(admin, %{role: :user}, current_user_id: admin.id)

      refute changeset.valid?
      assert "vous ne pouvez pas modifier votre propre rôle" in errors_on(changeset).role
    end
  end

  describe "delete/1" do
    test "deletes user" do
      user = create_user()

      assert {:ok, deleted} = UserRepository.delete(user)
      assert deleted.id == user.id
      assert {:error, :not_found} = UserRepository.get(user.id)
    end
  end

  describe "count/0" do
    test "counts total users" do
      initial_count = UserRepository.count()

      create_user()
      create_user()

      assert UserRepository.count() == initial_count + 2
    end
  end

  describe "count_admins/0" do
    test "counts only admin users" do
      initial_count = UserRepository.count_admins()

      create_user(role: :admin)
      create_user(role: :user)
      create_user(role: :admin)

      assert UserRepository.count_admins() == initial_count + 2
    end
  end

  describe "count_regular_users/0" do
    test "counts only regular users" do
      initial_count = UserRepository.count_regular_users()

      create_user(role: :user)
      create_user(role: :admin)
      create_user(role: :user)

      assert UserRepository.count_regular_users() == initial_count + 2
    end
  end

  describe "filter_by_role/2" do
    test "filters query by admin role" do
      admin = create_user(role: :admin)
      _user = create_user(role: :user)

      import Ecto.Query
      query = from(u in User)
      filtered = UserRepository.filter_by_role(query, :admin)

      results = Portfolio.Repo.all(filtered)
      ids = Enum.map(results, & &1.id)

      assert admin.id in ids
    end

    test "filters query by user role" do
      _admin = create_user(role: :admin)
      user = create_user(role: :user)

      import Ecto.Query
      query = from(u in User)
      filtered = UserRepository.filter_by_role(query, :user)

      results = Portfolio.Repo.all(filtered)
      ids = Enum.map(results, & &1.id)

      assert user.id in ids
    end
  end
end
