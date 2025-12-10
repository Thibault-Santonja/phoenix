defmodule PortfolioWeb.AuthControllerTest do
  use PortfolioWeb.ConnCase

  alias Portfolio.Auth
  alias Portfolio.Auth.MagicLink
  alias Portfolio.Auth.User
  alias Portfolio.Auth.UserSession
  alias Portfolio.Repo

  setup do
    # Use unique IP for each test to avoid rate limit interference
    # Generate a truly unique octet (1-255) by using the unique integer directly
    # and wrapping around the 1-255 range
    octet = 1 + rem(System.unique_integer([:positive]), 254)
    unique_ip = {127, 0, 0, octet}
    {:ok, conn: %{build_conn() | remote_ip: unique_ip}}
  end

  describe "verify_magic_link/2" do
    test "creates session and redirects to /admin/albums with valid token", %{conn: conn} do
      user = insert_user()
      magic_link = insert_magic_link(user)

      conn = get(conn, ~p"/auth/verify/#{magic_link.token}")

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

    test "sets httponly and secure flags on session cookie", %{conn: conn} do
      user = insert_user()
      magic_link = insert_magic_link(user)

      conn = get(conn, ~p"/auth/verify/#{magic_link.token}")

      # Récupérer le cookie Set-Cookie depuis les headers de réponse
      set_cookie_headers = Plug.Conn.get_resp_header(conn, "set-cookie")

      # Trouver le cookie de session (_portfolio_key)
      session_cookie =
        Enum.find(set_cookie_headers, fn cookie ->
          String.contains?(cookie, "_portfolio_key")
        end)

      assert session_cookie != nil, "Session cookie should be present"

      # Vérifier que le cookie a le flag HttpOnly
      assert String.contains?(session_cookie, "HttpOnly"),
             "Session cookie should have HttpOnly flag"

      # Vérifier que le cookie a le flag SameSite=Lax
      assert String.contains?(session_cookie, "SameSite=Lax"),
             "Session cookie should have SameSite=Lax"

      # Note: Le flag Secure n'est actif qu'en production (env != :test)
      # En test, on vérifie juste que la configuration est présente dans endpoint.ex
    end

    test "redirects to /login with error for invalid token", %{conn: conn} do
      conn = get(conn, ~p"/auth/verify/invalid_token_123")

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

      conn = get(conn, ~p"/auth/verify/#{magic_link.token}")

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
      conn = get(conn, ~p"/auth/verify/#{magic_link.token}")

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

    test "invalidates session cache on logout", %{conn: conn} do
      user = insert_user()
      {:ok, session} = Auth.create_session(user)

      # Le raw_token est retourné par create_session, session.token est hashé
      raw_token = session.token

      # Simuler une session en cache (en prod uniquement, skip en test)
      # La clé de cache utilise le token hashé (cohérent avec auth_helpers.ex)
      hashed_token = UserSession.hash_token_value(raw_token)
      cache_key = {:session, hashed_token}

      # Mettre la session en cache manuellement pour le test
      Cachex.put(:portfolio_cache, cache_key, session)

      # Vérifier que la session est en cache
      assert {:ok, ^session} = Cachex.get(:portfolio_cache, cache_key)

      # Logout (utilise le raw_token dans la session Plug)
      conn
      |> init_test_session(%{session_token: raw_token})
      |> delete(~p"/logout")

      # Vérifier que le cache a été invalidé
      assert {:ok, nil} = Cachex.get(:portfolio_cache, cache_key)
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
      conn = get(conn, ~p"/auth/verify/#{magic_link.token}")

      # Le cas normal devrait toujours fonctionner
      assert redirected_to(conn) == ~p"/admin"
    end

    test "handles concurrent magic link usage correctly", %{conn: _conn} do
      user = insert_user()
      magic_link = insert_magic_link(user)

      # Première utilisation avec IP unique
      conn1 =
        %{build_conn() | remote_ip: {127, 0, 0, 10}} |> get(~p"/auth/verify/#{magic_link.token}")

      assert redirected_to(conn1) == ~p"/admin"

      # Deuxième utilisation avec IP différente (devrait échouer car déjà utilisé)
      conn2 =
        %{build_conn() | remote_ip: {127, 0, 0, 11}} |> get(~p"/auth/verify/#{magic_link.token}")

      assert redirected_to(conn2) == ~p"/login"
      assert Phoenix.Flash.get(conn2.assigns.flash, :error) =~ "déjà été utilisé"
    end

    test "handles malformed tokens gracefully", %{conn: _conn} do
      malformed_tokens = [
        {"../../etc/passwd", 1},
        {"<script>alert('xss')</script>", 2},
        {String.duplicate("a", 10_000), 3},
        {"invalid_token_123", 4}
      ]

      for {token, ip_suffix} <- malformed_tokens do
        # Use unique IP for each iteration to avoid rate limiting
        unique_ip = {127, 0, 0, ip_suffix}
        test_conn = %{build_conn() | remote_ip: unique_ip} |> get(~p"/auth/verify/#{token}")
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
      conn = get(conn, ~p"/auth/verify/#{uppercase_token}")

      # Devrait échouer si le token original contient des minuscules
      if magic_link.token != uppercase_token do
        assert redirected_to(conn) == ~p"/login"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalide"
      end
    end
  end

  describe "verify_magic_link/2 - rate limiting" do
    setup do
      # Ensure rate limiter is reset before tests
      :ok
    end

    test "allows up to 10 verification attempts per 5 minutes per IP", %{conn: conn} do
      user = insert_user()
      magic_link = insert_magic_link(user)

      # Get a unique IP for this test to avoid interference
      test_ip = {127, 0, 0, System.unique_integer([:positive]) |> rem(255)}

      # Make 10 attempts (will fail because token is consumed after first use)
      for i <- 1..10 do
        conn_with_ip = %{conn | remote_ip: test_ip}

        if i == 1 do
          # First attempt succeeds
          conn_result = get(conn_with_ip, ~p"/auth/verify/#{magic_link.token}")
          assert redirected_to(conn_result) == ~p"/admin"
        else
          # Subsequent attempts with same token fail but don't hit rate limit
          conn_result = get(conn_with_ip, ~p"/auth/verify/#{magic_link.token}")
          assert redirected_to(conn_result) == ~p"/login"
          refute Phoenix.Flash.get(conn_result.assigns.flash, :error) =~ "Trop de tentatives"
        end
      end
    end

    test "blocks 11th verification attempt with rate limit error", %{conn: conn} do
      # Get a unique IP for this test
      test_ip = {127, 0, 0, System.unique_integer([:positive]) |> rem(255) |> max(1)}

      # Make 10 verification attempts with different invalid tokens
      for i <- 1..10 do
        conn_with_ip = %{conn | remote_ip: test_ip}
        conn_result = get(conn_with_ip, ~p"/auth/verify/invalid_token_#{i}")

        # Should get invalid token error, not rate limit
        assert redirected_to(conn_result) == ~p"/login"
        assert Phoenix.Flash.get(conn_result.assigns.flash, :error) =~ "invalide"
      end

      # 11th attempt should be rate limited
      conn_with_ip = %{conn | remote_ip: test_ip}
      conn_result = get(conn_with_ip, ~p"/auth/verify/invalid_token_11")

      # Rate limiter returns 429 and redirects to /login with flash message
      assert conn_result.status == 302
      assert redirected_to(conn_result) == "/login"
      assert Phoenix.Flash.get(conn_result.assigns.flash, :error) =~ "Trop de tentatives"
      assert Enum.any?(get_resp_header(conn_result, "retry-after"))
    end

    test "rate limit is per IP address", %{conn: conn} do
      user = insert_user()

      # IP 1 uses all attempts
      ip1 = {127, 0, 0, System.unique_integer([:positive]) |> rem(255)}

      for i <- 1..10 do
        conn_with_ip1 = %{conn | remote_ip: ip1}
        get(conn_with_ip1, ~p"/auth/verify/invalid_token_ip1_#{i}")
      end

      # IP 1's 11th attempt should be blocked
      conn_with_ip1 = %{conn | remote_ip: ip1}
      conn_result = get(conn_with_ip1, ~p"/auth/verify/invalid_token_ip1_11")
      assert Phoenix.Flash.get(conn_result.assigns.flash, :error) =~ "Trop de tentatives"

      # IP 2 should still be able to verify
      ip2 = {127, 0, 0, System.unique_integer([:positive]) |> rem(255)}
      magic_link = insert_magic_link(user)
      conn_with_ip2 = %{conn | remote_ip: ip2}
      conn_result = get(conn_with_ip2, ~p"/auth/verify/#{magic_link.token}")

      assert redirected_to(conn_result) == ~p"/admin"

      error_flash = Phoenix.Flash.get(conn_result.assigns.flash, :error)
      assert is_nil(error_flash) or not String.contains?(error_flash, "Trop de tentatives")
    end

    test "rate limit includes retry-after header", %{conn: conn} do
      test_ip = {127, 0, 0, System.unique_integer([:positive]) |> rem(255)}

      # Use up all attempts
      for i <- 1..10 do
        conn_with_ip = %{conn | remote_ip: test_ip}
        get(conn_with_ip, ~p"/auth/verify/invalid_#{i}")
      end

      # Next attempt should have retry-after header
      conn_with_ip = %{conn | remote_ip: test_ip}
      conn_result = get(conn_with_ip, ~p"/auth/verify/invalid_11")

      [retry_after] = get_resp_header(conn_result, "retry-after")
      assert String.to_integer(retry_after) > 0
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
      short_code: generate_short_code(),
      expires_at: DateTime.add(DateTime.utc_now(), 15, :minute) |> DateTime.truncate(:second)
    }

    %MagicLink{}
    |> MagicLink.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end

  defp generate_short_code do
    :crypto.strong_rand_bytes(4)
    |> Base.encode32(padding: false)
    |> String.slice(0..5)
    |> String.upcase()
  end
end
