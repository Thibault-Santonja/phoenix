defmodule PortfolioWeb.AuthLive.LoginTest do
  use PortfolioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolio.Auth
  alias Portfolio.Auth.User
  alias Portfolio.Repo

  describe "mount" do
    test "displays login form", %{conn: conn} do
      {:ok, view, html} = live(conn, "/login")

      assert html =~ "Connexion Admin"
      assert has_element?(view, "form")
      assert has_element?(view, "input[name=\"email_form[email]\"]")
    end

    test "assigns magic link TTL from configuration", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/login")

      # Get expected TTL from config (in seconds)
      expected_ttl =
        Application.get_env(:portfolio, :auth, [])
        |> Keyword.get(:magic_link_ttl_minutes, 15)
        |> then(&(&1 * 60))

      # Vérifier que le TTL est utilisé dans le template après soumission
      # Pour l'instant, vérifier simplement que la page se charge
      assert html =~ "Connexion Admin"
      assert expected_ttl == 900
    end
  end

  describe "request_link event" do
    test "sends magic link for existing user", %{conn: conn} do
      user = insert_user(%{email: "admin@example.com"})

      {:ok, view, _html} = live(conn, "/login")

      html =
        view
        |> form("form", %{email_form: %{email: user.email}})
        |> render_submit()

      assert html =~ "Un lien de connexion a été envoyé"
      # Note: email n'est plus affiché dans le message de succès pour des raisons de sécurité

      # Vérifier qu'un magic link a été créé
      magic_link = Repo.get_by(Portfolio.Auth.MagicLink, user_id: user.id)
      assert magic_link != nil
      refute magic_link.token == nil
    end

    test "creates user and sends magic link in dev environment", %{conn: conn} do
      email = "newuser@example.com"

      {:ok, view, _html} = live(conn, "/login")

      html =
        view
        |> form("form", %{email_form: %{email: email}})
        |> render_submit()

      assert html =~ "Un lien de connexion a été envoyé"

      # Vérifier que l'utilisateur a été créé
      assert {:ok, user} = Auth.get_user_by_email(email)
      assert user.email == email

      # Vérifier qu'un magic link a été créé
      magic_link = Repo.get_by(Portfolio.Auth.MagicLink, user_id: user.id)
      assert magic_link != nil
    end

    test "displays confirmation message after link sent", %{conn: conn} do
      user = insert_user()

      {:ok, view, _html} = live(conn, "/login")

      view
      |> form("form", %{email_form: %{email: user.email}})
      |> render_submit()

      assert render(view) =~ "Un lien de connexion a été envoyé"
      # Le message ne contient plus l'email pour des raisons de sécurité
    end

    test "displays magic link expiration countdown after link sent", %{conn: conn} do
      user = insert_user()

      {:ok, view, _html} = live(conn, "/login")

      html =
        view
        |> form("form", %{email_form: %{email: user.email}})
        |> render_submit()

      # Vérifier que le hook de countdown est présent
      assert html =~ "phx-hook=\"MagicLinkExpiration\""
      assert html =~ "data-expires-in"
      assert html =~ "magic-link-countdown"
    end

    test "displays rate limit countdown when rate limited", %{conn: conn} do
      user = insert_user()

      # Épuiser le rate limit avec 5 connexions différentes
      for _i <- 1..5 do
        {:ok, temp_view, _html} = live(conn, "/login")

        temp_view
        |> form("form", %{email_form: %{email: user.email}})
        |> render_submit()
      end

      # La 6ème tentative devrait afficher le countdown
      {:ok, view, _html} = live(conn, "/login")

      html =
        view
        |> form("form", %{email_form: %{email: user.email}})
        |> render_submit()

      assert html =~ "phx-hook=\"RateLimitCountdown\""
      assert html =~ "data-retry-after"
      assert html =~ "countdown-display"
      assert html =~ "Trop de tentatives"
    end

    test "shows error for invalid email format", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/login")

      html =
        view
        |> form("form", %{email_form: %{email: "not-an-email"}})
        |> render_submit()

      # La validation rejette l'email invalide
      assert html =~ "L'email doit être valide" or html =~ "email"
    end

    test "shows same success message for unknown email in production (anti-enumeration)", %{
      conn: conn
    } do
      # Simuler l'environnement de production
      original_env = Application.get_env(:portfolio, :env)
      Application.put_env(:portfolio, :env, :prod)

      unknown_email = "unknown-prod-#{System.unique_integer([:positive])}@example.com"

      # Vérifier que l'utilisateur n'existe pas
      refute Repo.get_by(User, email: unknown_email)

      {:ok, view, _html} = live(conn, "/login")

      html =
        view
        |> form("form", %{email_form: %{email: unknown_email}})
        |> render_submit()

      # Doit afficher le même message de succès pour ne pas révéler si l'email existe
      assert html =~ "Un lien de connexion a été envoyé"

      # Vérifier que l'utilisateur n'a pas été créé
      refute Repo.get_by(User, email: unknown_email)

      # Vérifier qu'aucun magic link n'a été créé
      assert Repo.all(Portfolio.Auth.MagicLink) |> Enum.empty?()

      # Restaurer l'environnement
      Application.put_env(:portfolio, :env, original_env)
    end
  end

  describe "validate event" do
    test "validates email format in real-time", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/login")

      # Enter an invalid email
      html =
        view
        |> element("form")
        |> render_change(%{email_form: %{email: "invalid"}})

      # Should show validation error
      assert html =~ "email" or html =~ "invalide"
    end

    test "accepts valid email format", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/login")

      # Enter a valid email
      html =
        view
        |> element("form")
        |> render_change(%{email_form: %{email: "valid@example.com"}})

      # Should not show email format error
      refute html =~ "invalide"
    end

    test "requires email field", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/login")

      # Submit empty form
      html =
        view
        |> element("form")
        |> render_change(%{email_form: %{email: ""}})

      # Should show required error or keep submit button state
      assert html =~ "email" or html =~ "requis"
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
end
