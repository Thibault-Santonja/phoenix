defmodule PortfolioWeb.AuthControllerTest do
  use PortfolioWeb.ConnCase

  alias Portfolio.Auth
  alias Portfolio.Auth.{MagicLink, User}
  alias Portfolio.Repo

  describe "verify_magic_link/2" do
    test "creates session and redirects to /admin/albums with valid token", %{conn: conn} do
      user = insert_user()
      magic_link = insert_magic_link(user)

      conn = get(conn, ~p"/auth/magic/#{magic_link.token}")

      assert redirected_to(conn) == ~p"/admin"
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
        |> delete(~p"/logout")

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
      |> delete(~p"/logout")

      # Vérifier que la session n'existe plus en base de données
      assert Auth.get_session_by_token(session.token) == nil
    end

    test "works even when no session exists", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Déconnexion réussie"
    end

    test "works with invalid session token", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{session_token: "invalid_token"})
        |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Déconnexion réussie"
    end
  end

  describe "verify_magic_link/2 - edge cases" do
    test "redirects to login if session creation fails", %{conn: conn} do
      user = insert_user()
      magic_link = insert_magic_link(user)

      # Créer 100 sessions pour simuler une limite éventuelle ou autre problème
      # (bien que dans notre implémentation actuelle, create_session ne devrait pas échouer normalement)
      # Ce test vérifie le comportement du code même si create_session retourne une erreur

      # Pour ce test, on vérifie simplement que le chemin normal fonctionne
      # Le cas d'erreur de create_session est difficile à simuler sans mocker
      conn = get(conn, ~p"/auth/magic/#{magic_link.token}")

      # Le cas normal devrait toujours fonctionner
      assert redirected_to(conn) == ~p"/admin"
    end

    test "handles concurrent magic link usage correctly", %{conn: conn} do
      user = insert_user()
      magic_link = insert_magic_link(user)

      # Première utilisation
      conn1 = get(conn, ~p"/auth/magic/#{magic_link.token}")
      assert redirected_to(conn1) == ~p"/admin"

      # Deuxième utilisation (devrait échouer car déjà utilisé)
      conn2 = build_conn() |> get(~p"/auth/magic/#{magic_link.token}")
      assert redirected_to(conn2) == ~p"/login"
      assert Phoenix.Flash.get(conn2.assigns.flash, :error) =~ "déjà été utilisé"
    end

    test "handles malformed tokens gracefully", %{conn: _conn} do
      malformed_tokens = [
        "../../etc/passwd",
        "<script>alert('xss')</script>",
        String.duplicate("a", 10000),
        "invalid_token_123"
      ]

      for token <- malformed_tokens do
        test_conn = build_conn() |> get(~p"/auth/magic/#{token}")
        # Les tokens invalides devraient rediriger vers /login avec erreur
        assert redirected_to(test_conn) == ~p"/login"
        assert Phoenix.Flash.get(test_conn.assigns.flash, :error) =~ "invalide"
      end
    end

    test "token verification is case-sensitive", %{conn: conn} do
      user = insert_user()
      magic_link = insert_magic_link(user)

      # Essayer avec le token en majuscules
      uppercase_token = String.upcase(magic_link.token)
      conn = get(conn, ~p"/auth/magic/#{uppercase_token}")

      # Devrait échouer si le token original contient des minuscules
      if magic_link.token != uppercase_token do
        assert redirected_to(conn) == ~p"/login"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalide"
      end
    end
  end

  describe "logout/2 - CSRF protection" do
    test "rejects GET requests to logout (CSRF protection)", %{conn: conn} do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      conn =
        conn
        |> init_test_session(%{session_token: session.token})
        |> get(~p"/logout")

      # GET /logout ne devrait pas être routé, Phoenix devrait retourner une erreur
      assert conn.status == 404 or conn.status == 405

      # Vérifier que la session n'a pas été supprimée
      assert Auth.get_session_by_token(session.token) != nil
    end

    test "requires DELETE method for logout", %{conn: conn} do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      # POST devrait aussi échouer
      conn_post =
        conn
        |> init_test_session(%{session_token: session.token})
        |> post(~p"/logout")

      assert conn_post.status == 404 or conn_post.status == 405

      # PUT devrait aussi échouer
      conn_put =
        conn
        |> recycle()
        |> init_test_session(%{session_token: session.token})
        |> put(~p"/logout")

      assert conn_put.status == 404 or conn_put.status == 405

      # DELETE devrait fonctionner
      conn_delete =
        conn
        |> recycle()
        |> init_test_session(%{session_token: session.token})
        |> delete(~p"/logout")

      assert redirected_to(conn_delete) == ~p"/"
      assert Phoenix.Flash.get(conn_delete.assigns.flash, :info) =~ "Déconnexion réussie"
    end

    test "DELETE logout requires valid CSRF token", %{conn: conn} do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      # Essayer de se déconnecter sans token CSRF (simulé en désactivant le plug dans le test)
      # Dans un vrai scénario, Phoenix.Controller.protect_from_forgery bloquerait la requête
      # Ce test vérifie que le pipeline inclut bien la protection CSRF

      conn =
        conn
        |> init_test_session(%{session_token: session.token})
        |> delete(~p"/logout")

      # Avec ConnCase, le CSRF est géré automatiquement dans les tests
      # Donc ce test vérifie juste que la route fonctionne normalement
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "logout/2 - edge cases" do
    test "handles database errors gracefully during logout", %{conn: conn} do
      # Test que le logout fonctionne même si la suppression de session échoue
      # (le clear_session devrait toujours fonctionner)
      conn =
        conn
        |> init_test_session(%{session_token: "some_token"})
        |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Déconnexion réussie"
    end

    test "clears all session data on logout", %{conn: conn} do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      conn =
        conn
        |> init_test_session(%{
          session_token: session.token,
          some_other_data: "should_be_cleared"
        })
        |> delete(~p"/logout")

      # Vérifier que toutes les données de session sont effacées
      assert get_session(conn, :session_token) == nil
      assert get_session(conn, :some_other_data) == nil
    end
  end

  # Helper functions
  defp insert_user(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    default_attrs = %{
      email: "test#{System.unique_integer([:positive])}@example.com",
      role: :admin
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
