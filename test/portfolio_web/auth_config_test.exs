defmodule PortfolioWeb.AuthConfigTest do
  @moduledoc """
  Tests pour le module AuthConfig qui centralise la configuration d'authentification.
  """

  use ExUnit.Case, async: true

  alias PortfolioWeb.AuthConfig

  describe "messages" do
    test "unauthenticated_message/0 returns consistent error message" do
      message = AuthConfig.unauthenticated_message()
      assert is_binary(message)
      assert message =~ "connecté"
    end

    test "unauthorized_message/0 returns consistent error message" do
      message = AuthConfig.unauthorized_message()
      assert is_binary(message)
      assert message =~ "permissions"
    end
  end

  describe "paths" do
    test "login_path/0 returns login route" do
      assert AuthConfig.login_path() == "/login"
    end

    test "authenticated_path/0 returns admin route" do
      assert AuthConfig.authenticated_path() == "/admin"
    end

    test "unauthorized_path/0 returns home route" do
      assert AuthConfig.unauthorized_path() == "/"
    end
  end

  describe "admin_roles/0" do
    test "returns list of admin roles" do
      roles = AuthConfig.admin_roles()
      assert is_list(roles)
      assert :admin in roles
    end
  end

  describe "admin_role?/1" do
    test "returns true for admin role" do
      assert AuthConfig.admin_role?(:admin) == true
    end

    test "returns false for user role" do
      assert AuthConfig.admin_role?(:user) == false
    end

    test "returns false for unknown role" do
      assert AuthConfig.admin_role?(:unknown) == false
    end

    test "returns false for nil" do
      assert AuthConfig.admin_role?(nil) == false
    end
  end
end
