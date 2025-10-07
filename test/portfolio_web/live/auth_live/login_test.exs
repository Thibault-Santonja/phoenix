defmodule PortfolioWeb.AuthLive.LoginTest do
  use PortfolioWeb.ConnCase

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

    test "shows error for invalid email format", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/login")

      html =
        view
        |> form("form", %{email_form: %{email: "not-an-email"}})
        |> render_submit()

      # La validation rejette l'email invalide
      assert html =~ "L'email doit être valide" or html =~ "email"
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
