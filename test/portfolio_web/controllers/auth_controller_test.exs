defmodule PortfolioWeb.AuthControllerTest do
  use PortfolioWeb.ConnCase

  alias Portfolio.Auth
  alias Portfolio.Auth.{User, MagicLink}
  alias Portfolio.Repo

  describe "verify_magic_link/2" do
    test "creates session and redirects to /admin/albums with valid token", %{conn: conn} do
      user = insert_user()
      magic_link = insert_magic_link(user)

      conn = get(conn, ~p"/auth/magic/#{magic_link.token}")

      assert redirected_to(conn) == ~p"/admin/albums"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Connexion réussie"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ user.email

      # Vérifier qu'une session a été créée
      session_token = get_session(conn, :session_token)
      assert session_token != nil

      # Vérifier que la session existe en base de données
      session = Auth.get_session_by_token(session_token)
      assert session != nil
      assert session.user_id == user.id

      # Vérifier que le magic link a été marqué comme utilisé
      updated_magic_link = Repo.get!(MagicLink, magic_link.id)
      assert updated_magic_link.used_at != nil
    end

    test "redirects to /login with error for invalid token", %{conn: conn} do
      conn = get(conn, ~p"/auth/magic/invalid_token_123")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Lien de connexion invalide"

      # Vérifier qu'aucune session n'a été créée
      session_token = get_session(conn, :session_token)
      assert session_token == nil
    end

    test "redirects to /login with error for expired token", %{conn: conn} do
      user = insert_user()

      # Créer un magic link expiré
      expired_at = DateTime.add(DateTime.utc_now(), -1, :hour) |> DateTime.truncate(:second)
      magic_link = insert_magic_link(user, expires_at: expired_at)

      conn = get(conn, ~p"/auth/magic/#{magic_link.token}")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "a expiré"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "nouveau lien"

      # Vérifier qu'aucune session n'a été créée
      session_token = get_session(conn, :session_token)
      assert session_token == nil
    end

    test "redirects to /login with error for already used token", %{conn: conn} do
      user = insert_user()
      magic_link = insert_magic_link(user)

      # Utiliser le magic link une première fois
      {:ok, _user} = Auth.verify_magic_link(magic_link.token)

      # Essayer de l'utiliser à nouveau
      conn = get(conn, ~p"/auth/magic/#{magic_link.token}")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "déjà été utilisé"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "nouveau lien"

      # Vérifier qu'aucune session n'a été créée
      session_token = get_session(conn, :session_token)
      assert session_token == nil
    end
  end

  describe "logout/2" do
    test "clears session and redirects to /", %{conn: conn} do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      conn =
        conn
        |> init_test_session(%{session_token: session.token})
        |> get(~p"/logout")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Déconnexion réussie"

      # Vérifier que la session a été supprimée
      session_token = get_session(conn, :session_token)
      assert session_token == nil
    end

    test "deletes session from database", %{conn: conn} do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      conn
      |> init_test_session(%{session_token: session.token})
      |> get(~p"/logout")

      # Vérifier que la session n'existe plus en base de données
      assert Auth.get_session_by_token(session.token) == nil
    end

    test "works even when no session exists", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get(~p"/logout")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Déconnexion réussie"
    end

    test "works with invalid session token", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{session_token: "invalid_token"})
        |> get(~p"/logout")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Déconnexion réussie"
    end
  end

  # Helper functions
  defp insert_user(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      email: "test#{System.unique_integer([:positive])}@example.com",
      role: "admin"
    }

    %User{}
    |> User.registration_changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp insert_magic_link(user, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      user_id: user.id,
      token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      expires_at: DateTime.add(DateTime.utc_now(), 15, :minute) |> DateTime.truncate(:second)
    }

    %MagicLink{}
    |> MagicLink.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end
end
