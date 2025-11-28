defmodule PortfolioWeb.LiveAuthTest do
  use Portfolio.DataCase, async: true

  import PortfolioTest.Fixtures.AuthFixtures

  alias PortfolioWeb.LiveAuth

  describe "on_mount/4" do
    test "assigns nil current_user when no session token" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}}
      }

      session = %{}

      assert {:cont, updated_socket} = LiveAuth.on_mount(:default, %{}, session, socket)
      assert updated_socket.assigns.current_user == nil
    end

    test "assigns nil current_user when session token is invalid" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}}
      }

      session = %{"session_token" => "invalid_token"}

      assert {:cont, updated_socket} = LiveAuth.on_mount(:default, %{}, session, socket)
      assert updated_socket.assigns.current_user == nil
    end

    test "assigns current_user from valid session token" do
      user = create_user()
      user_session = create_session(user: user)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}}
      }

      session = %{"session_token" => user_session.token}

      assert {:cont, updated_socket} = LiveAuth.on_mount(:default, %{}, session, socket)
      assert updated_socket.assigns.current_user.id == user.id
    end

    test "preserves existing current_user from assigns" do
      user = create_user()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, current_user: user}
      }

      session = %{}

      assert {:cont, updated_socket} = LiveAuth.on_mount(:default, %{}, session, socket)
      assert updated_socket.assigns.current_user.id == user.id
    end

    test "assigns nil when session token is not a binary" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}}
      }

      session = %{"session_token" => nil}

      assert {:cont, updated_socket} = LiveAuth.on_mount(:default, %{}, session, socket)
      assert updated_socket.assigns.current_user == nil
    end

    test "assigns nil when session token key is missing" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}}
      }

      session = %{"other_key" => "value"}

      assert {:cont, updated_socket} = LiveAuth.on_mount(:default, %{}, session, socket)
      assert updated_socket.assigns.current_user == nil
    end
  end
end
