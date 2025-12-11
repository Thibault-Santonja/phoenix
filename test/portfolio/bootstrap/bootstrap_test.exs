defmodule Portfolio.BootstrapTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Auth.User
  alias Portfolio.Bootstrap
  alias Portfolio.Repo

  describe "run/1" do
    test "creates admin user when user does not exist" do
      email = "new-admin-#{System.unique_integer([:positive])}@example.com"

      assert :ok = Bootstrap.run(admin_email: email)

      user = Repo.get_by(User, email: email)
      assert user != nil
      assert user.role == :admin
      assert user.email == email
    end

    test "promotes existing user to admin if not already admin" do
      # Create a regular user first
      email = "existing-user-#{System.unique_integer([:positive])}@example.com"

      {:ok, user} =
        %User{}
        |> User.registration_changeset(%{email: email, name: "Test User"})
        |> Repo.insert()

      assert user.role == :user

      # Run bootstrap should promote to admin
      assert :ok = Bootstrap.run(admin_email: email)

      updated_user = Repo.get!(User, user.id)
      assert updated_user.role == :admin
    end

    test "does nothing if user is already admin" do
      email = "admin-#{System.unique_integer([:positive])}@example.com"

      # Create an admin user
      {:ok, user} =
        %User{}
        |> User.bootstrap_admin_changeset(%{email: email, name: "Admin", role: :admin})
        |> Repo.insert()

      assert user.role == :admin

      # Run bootstrap should not change anything
      assert :ok = Bootstrap.run(admin_email: email)

      unchanged_user = Repo.get!(User, user.id)
      assert unchanged_user.role == :admin
      assert unchanged_user.updated_at == user.updated_at
    end

    test "extracts name from email correctly" do
      email = "john.doe-#{System.unique_integer([:positive])}@example.com"

      assert :ok = Bootstrap.run(admin_email: email)

      user = Repo.get_by(User, email: email)
      # Name is extracted from email prefix, split by dots and capitalized
      assert user.name =~ "John"
    end
  end

  describe "repo_ready?/0" do
    test "returns true when repo is available" do
      assert Bootstrap.repo_ready?() == true
    end
  end

  describe "config/1" do
    test "returns max_retries from application config" do
      # Default is nil if not configured, or the configured value
      result = Bootstrap.config(:max_retries)
      assert is_nil(result) or is_integer(result)
    end

    test "returns retry_interval_ms from application config" do
      result = Bootstrap.config(:retry_interval_ms)
      assert is_nil(result) or is_integer(result)
    end

    test "returns admin_email from environment or default" do
      result = Bootstrap.config(:admin_email)
      assert is_binary(result)
      assert String.contains?(result, "@")
    end
  end
end
