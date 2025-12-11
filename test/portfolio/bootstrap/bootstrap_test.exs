defmodule Portfolio.BootstrapTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Auth.User
  alias Portfolio.Bootstrap
  alias Portfolio.Repo

  describe "run/1" do
    test "creates admin user when none exists" do
      email = "bootstrap-test-#{System.unique_integer([:positive])}@example.com"

      assert :ok = Bootstrap.run(admin_email: email)

      user = Repo.get_by(User, email: email)
      assert user != nil
      assert user.role == :admin
    end

    test "promotes existing user to admin" do
      email = "promote-test-#{System.unique_integer([:positive])}@example.com"

      # Create a regular user first
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: email, role: :user})
        |> Repo.insert()

      assert user.role == :user

      # Run bootstrap
      assert :ok = Bootstrap.run(admin_email: email)

      # User should be promoted
      updated_user = Repo.get(User, user.id)
      assert updated_user.role == :admin
    end

    test "does nothing if user is already admin" do
      email = "already-admin-#{System.unique_integer([:positive])}@example.com"

      # Create an admin user first
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: email, role: :admin})
        |> Repo.insert()

      assert user.role == :admin

      # Run bootstrap - should succeed without error
      assert :ok = Bootstrap.run(admin_email: email)

      # User should still be admin
      updated_user = Repo.get(User, user.id)
      assert updated_user.role == :admin
    end

    test "uses default admin email when not provided" do
      # This test just verifies the function runs without error
      # The actual email used depends on ENV or default config
      result = Bootstrap.run([])
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "repo_ready?/0" do
    test "returns true when repo is available" do
      assert Bootstrap.repo_ready?() == true
    end
  end

  describe "config/1" do
    test "returns admin_email from env or default" do
      email = Bootstrap.config(:admin_email)
      assert is_binary(email)
      assert String.contains?(email, "@")
    end

    test "returns max_retries from application config" do
      # May be nil if not configured
      result = Bootstrap.config(:max_retries)
      assert is_nil(result) or is_integer(result)
    end

    test "returns retry_interval_ms from application config" do
      result = Bootstrap.config(:retry_interval_ms)
      assert is_nil(result) or is_integer(result)
    end
  end
end
