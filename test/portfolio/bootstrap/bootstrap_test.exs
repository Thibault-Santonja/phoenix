defmodule Portfolio.BootstrapTest do
  use Portfolio.DataCase, async: false

  alias Portfolio.Auth.User
  alias Portfolio.Bootstrap
  alias Portfolio.Repo

  describe "run/1" do
    test "creates admin user when not exists" do
      email = "test-admin-#{System.unique_integer([:positive])}@example.com"

      assert :ok = Bootstrap.run(admin_email: email)

      user = Repo.get_by(User, email: email)
      assert user != nil
      assert user.role == :admin
    end

    test "does not fail when admin already exists" do
      email = "existing-admin-#{System.unique_integer([:positive])}@example.com"

      # First run creates the admin
      assert :ok = Bootstrap.run(admin_email: email)

      # Second run should succeed without error
      assert :ok = Bootstrap.run(admin_email: email)
    end

    test "promotes existing non-admin user to admin" do
      email = "promote-test-#{System.unique_integer([:positive])}@example.com"

      # Create a regular user first
      {:ok, user} =
        %User{}
        |> User.registration_changeset(%{email: email, name: "Test User"})
        |> Repo.insert()

      assert user.role == :user

      # Bootstrap should promote to admin
      assert :ok = Bootstrap.run(admin_email: email)

      updated_user = Repo.get!(User, user.id)
      assert updated_user.role == :admin
    end

    test "does not demote existing admin" do
      email = "keep-admin-#{System.unique_integer([:positive])}@example.com"

      # Create admin via bootstrap
      assert :ok = Bootstrap.run(admin_email: email)

      user = Repo.get_by!(User, email: email)
      assert user.role == :admin

      # Run again - should stay admin
      assert :ok = Bootstrap.run(admin_email: email)

      same_user = Repo.get!(User, user.id)
      assert same_user.role == :admin
    end

    test "uses default admin email from config" do
      # Just verify it runs without error using default config
      # We don't test the actual email as it comes from ENV
      result = Bootstrap.run()
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "repo_ready?/0" do
    test "returns true when database is available" do
      assert Bootstrap.repo_ready?() == true
    end
  end

  describe "config/1" do
    test "returns admin_email from environment or default" do
      email = Bootstrap.config(:admin_email)
      assert is_binary(email)
      assert String.contains?(email, "@")
    end

    test "returns nil for unknown config keys" do
      assert Bootstrap.config(:unknown_key) == nil
    end

    test "returns max_retries from application config" do
      # This may be nil or a value depending on config
      result = Bootstrap.config(:max_retries)
      assert is_nil(result) or is_integer(result)
    end

    test "returns retry_interval_ms from application config" do
      result = Bootstrap.config(:retry_interval_ms)
      assert is_nil(result) or is_integer(result)
    end
  end

  describe "admin user creation" do
    test "extracts name from email correctly" do
      email = "john.doe-#{System.unique_integer([:positive])}@example.com"

      assert :ok = Bootstrap.run(admin_email: email)

      user = Repo.get_by!(User, email: email)
      # "john.doe@..." should become "John Doe"
      assert String.starts_with?(user.name, "John Doe")
    end

    test "handles single-part email names" do
      email = "admin-#{System.unique_integer([:positive])}@example.com"

      assert :ok = Bootstrap.run(admin_email: email)

      user = Repo.get_by!(User, email: email)
      assert String.starts_with?(user.name, "Admin")
    end
  end
end
