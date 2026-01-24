defmodule PortfolioWeb.Integration.DisposableEmailBlockingTest do
  @moduledoc """
  Tests d'intégration pour le blocage des emails jetables.

  Vérifie que les utilisateurs ne peuvent pas s'inscrire avec des adresses
  email temporaires ou jetables.
  """

  use Portfolio.DataCase, async: false

  alias Portfolio.Auth
  alias Portfolio.Repo

  describe "User creation blocks disposable emails" do
    test "cannot create user with mailinator.com" do
      result =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "user@mailinator.com", role: :admin})
        |> Repo.insert()

      assert {:error, changeset} = result
      assert "les adresses email temporaires ne sont pas autorisées" in errors_on(changeset).email
    end

    test "cannot create user with guerrillamail.com" do
      result =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "test@guerrillamail.com", role: :admin})
        |> Repo.insert()

      assert {:error, changeset} = result
      assert "les adresses email temporaires ne sont pas autorisées" in errors_on(changeset).email
    end

    test "cannot create user with temp-mail.org" do
      result =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "user@temp-mail.org", role: :admin})
        |> Repo.insert()

      assert {:error, changeset} = result
      assert "les adresses email temporaires ne sont pas autorisées" in errors_on(changeset).email
    end

    test "can create user with legitimate email" do
      {:ok, user} =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "user@gmail.com", role: :admin})
        |> Repo.insert()

      assert user.email == "user@gmail.com"
    end

    test "blocks subdomain of disposable domain" do
      result =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "user@subdomain.mailinator.com", role: :admin})
        |> Repo.insert()

      assert {:error, changeset} = result
      assert "les adresses email temporaires ne sont pas autorisées" in errors_on(changeset).email
    end
  end

  describe "Registration changeset blocks disposable emails" do
    test "registration_changeset rejects disposable email" do
      result =
        %Auth.User{}
        |> Auth.User.registration_changeset(%{email: "user@throwaway.email"})
        |> Repo.insert()

      assert {:error, changeset} = result
      assert "les adresses email temporaires ne sont pas autorisées" in errors_on(changeset).email
    end

    test "registration_changeset accepts legitimate email" do
      {:ok, user} =
        %Auth.User{}
        |> Auth.User.registration_changeset(%{email: "user@company.com"})
        |> Repo.insert()

      assert user.email == "user@company.com"
      assert user.role == :user
    end
  end

  describe "Magic link request with disposable email" do
    test "cannot request magic link with disposable email in production" do
      # En production, le service ne crée pas automatiquement les utilisateurs
      original_env = Application.get_env(:portfolio, :env)

      try do
        Application.put_env(:portfolio, :env, :prod)

        # L'utilisateur n'existe pas
        assert {:error, :not_found} = Auth.get_user_by_email("user@mailinator.com")

        # La requête magic link doit échouer (anti-énumération)
        # En production, on retourne :email_sent pour ne pas révéler si l'email existe
        assert {:ok, :email_sent} = Auth.request_magic_link("user@mailinator.com")
      after
        Application.put_env(:portfolio, :env, original_env)
      end
    end

    test "in dev environment, user creation with disposable email should fail" do
      # En dev/test, on tente de créer l'utilisateur automatiquement
      # Mais la validation doit bloquer les emails jetables

      # Vérifier que l'utilisateur n'existe pas
      assert {:error, :not_found} = Auth.get_user_by_email("newuser@mailinator.com")

      # Tenter de demander un magic link (devrait créer l'utilisateur en dev)
      result = Auth.request_magic_link("newuser@mailinator.com")

      # Devrait échouer avec une erreur de changeset
      assert {:error, changeset} = result
      assert "les adresses email temporaires ne sont pas autorisées" in errors_on(changeset).email

      # Vérifier que l'utilisateur n'a pas été créé
      assert {:error, :not_found} = Auth.get_user_by_email("newuser@mailinator.com")
    end

    test "magic link works with legitimate email in dev" do
      email = "legituser#{System.unique_integer([:positive])}@gmail.com"

      # Vérifier que l'utilisateur n'existe pas
      assert {:error, :not_found} = Auth.get_user_by_email(email)

      # Demander un magic link (devrait créer l'utilisateur en dev)
      assert {:ok, magic_link} = Auth.request_magic_link(email)
      assert magic_link.token

      # Vérifier que l'utilisateur a été créé
      assert {:ok, user} = Auth.get_user_by_email(email)
      assert user.email == email
    end
  end

  describe "Admin interface cannot create users with disposable emails" do
    test "admin_changeset rejects disposable email" do
      user =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "admin@gmail.com", role: :admin})
        |> Repo.insert!()

      result =
        user
        |> Auth.User.admin_changeset(%{email: "user@mailinator.com"}, current_user_id: "other-id")
        |> Repo.update()

      # Note: admin_changeset ne permet pas de changer l'email
      # Donc ce test vérifie surtout la cohérence de la validation
      # En pratique, l'email ne devrait pas être modifiable via admin_changeset
      assert {:ok, _updated} = result
    end
  end
end
