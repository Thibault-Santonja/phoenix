defmodule PortfolioWeb.Plugs.RequireAuthTest do
  use PortfolioWeb.ConnCase, async: true

  import Plug.Conn

  alias Portfolio.Auth
  alias Portfolio.Auth.User
  alias Portfolio.Repo
  alias PortfolioWeb.Plugs.RequireAuth

  describe "fetch_current_user/2" do
    test "assigns current_user when session token is valid", %{conn: conn} do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      conn =
        conn
        |> init_test_session(%{session_token: session.token})
        |> RequireAuth.call(:fetch_current_user)

      assert conn.assigns.current_user.id == user.id
      assert conn.assigns.current_session.id == session.id
    end

    test "assigns nil when no session token", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> RequireAuth.call(:fetch_current_user)

      assert conn.assigns.current_user == nil
      refute Map.has_key?(conn.assigns, :current_session)
    end

    test "clears session and assigns nil when session token is invalid", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{session_token: "invalid_token"})
        |> RequireAuth.call(:fetch_current_user)

      assert conn.assigns.current_user == nil
      assert get_session(conn, :session_token) == nil
    end

    test "clears session when session has expired", %{conn: conn} do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      # Marquer la session comme expirée (inactivité de 31 jours)
      expired_at = DateTime.add(DateTime.utc_now(), -31, :day) |> DateTime.truncate(:second)

      session
      |> Ecto.Changeset.change(%{last_activity_at: expired_at})
      |> Repo.update!()

      conn =
        conn
        |> init_test_session(%{session_token: session.token})
        |> RequireAuth.call(:fetch_current_user)

      assert conn.assigns.current_user == nil
      assert get_session(conn, :session_token) == nil
    end

    test "updates session activity when fetching current user", %{conn: conn} do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      # Modifier la session pour avoir une activité ancienne (> 5 minutes)
      # pour dépasser le throttling et forcer la mise à jour
      old_activity = DateTime.add(DateTime.utc_now(), -6, :minute) |> DateTime.truncate(:second)

      session
      |> Ecto.Changeset.change(%{last_activity_at: old_activity})
      |> Repo.update!()

      conn
      |> init_test_session(%{session_token: session.token})
      |> RequireAuth.call(:fetch_current_user)

      # Vérifier que l'activité a été mise à jour
      updated_session = Repo.get!(Portfolio.Auth.UserSession, session.id)
      assert DateTime.compare(updated_session.last_activity_at, old_activity) == :gt
    end

    test "reloads user with fresh role data on each request", %{conn: conn} do
      user = insert_user(%{role: :user})
      {:ok, session} = Auth.create_session(user)

      # Première requête : le user doit avoir le rôle :user
      conn1 =
        conn
        |> init_test_session(%{session_token: session.token})
        |> RequireAuth.call(:fetch_current_user)

      assert conn1.assigns.current_user.role == :user

      # Modifier le rôle de l'utilisateur en base de données
      {:ok, _updated_user} = Auth.update_user_as_admin(user, %{role: :admin})

      # Deuxième requête : le user doit avoir le nouveau rôle :admin
      # (même si la session est en cache)
      conn2 =
        build_conn()
        |> init_test_session(%{session_token: session.token})
        |> RequireAuth.call(:fetch_current_user)

      assert conn2.assigns.current_user.role == :admin
    end

    test "fresh role data allows access to admin routes immediately", %{conn: conn} do
      user = insert_user(%{role: :user})
      {:ok, session} = Auth.create_session(user)

      # Première requête : le user ne peut pas accéder aux routes admin
      conn1 =
        conn
        |> init_test_session(%{session_token: session.token})
        |> fetch_flash()
        |> RequireAuth.call(:fetch_current_user)
        |> RequireAuth.call(:require_admin_role)

      assert conn1.halted
      assert redirected_to(conn1) == "/"

      # Promouvoir l'utilisateur en admin
      {:ok, _updated_user} = Auth.update_user_as_admin(user, %{role: :admin})

      # Deuxième requête : le user peut maintenant accéder aux routes admin
      conn2 =
        build_conn()
        |> init_test_session(%{session_token: session.token})
        |> fetch_flash()
        |> RequireAuth.call(:fetch_current_user)
        |> RequireAuth.call(:require_admin_role)

      refute conn2.halted
    end
  end

  describe "require_authenticated_user/2" do
    test "allows request when current_user is assigned", %{conn: conn} do
      user = insert_user()

      conn =
        conn
        |> assign(:current_user, user)
        |> RequireAuth.call(:require_authenticated_user)

      refute conn.halted
    end

    test "redirects to /login when current_user is nil", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:current_user, nil)
        |> RequireAuth.call(:require_authenticated_user)

      assert conn.halted
      assert redirected_to(conn) == "/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Vous devez être connecté"
    end

    test "redirects to /login when current_user is not assigned", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireAuth.call(:require_authenticated_user)

      assert conn.halted
      assert redirected_to(conn) == "/login"
    end
  end

  describe "require_admin_role/2" do
    test "allows request when user has admin role", %{conn: conn} do
      user = insert_user(%{role: :admin})

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:current_user, user)
        |> RequireAuth.call(:require_admin_role)

      refute conn.halted
    end

    test "redirects to / when current_user is nil", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:current_user, nil)
        |> RequireAuth.call(:require_admin_role)

      assert conn.halted
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Vous n'avez pas les permissions"
    end

    test "redirects to / when current_user is not assigned", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireAuth.call(:require_admin_role)

      assert conn.halted
      assert redirected_to(conn) == "/"
    end
  end

  # Helper functions
  defp insert_user(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      email: "test#{System.unique_integer([:positive])}@example.com",
      role: :admin
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    # Use bootstrap_admin_changeset for tests
    changeset = %User{} |> User.bootstrap_admin_changeset(merged_attrs)

    Repo.insert!(changeset)
  end
end
