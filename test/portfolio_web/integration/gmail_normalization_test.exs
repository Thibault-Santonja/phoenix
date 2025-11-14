defmodule PortfolioWeb.Integration.GmailNormalizationTest do
  @moduledoc """
  Tests d'intégration pour la normalisation Gmail.

  Vérifie que les adresses Gmail avec des points sont correctement normalisées
  et qu'un utilisateur ne peut pas créer plusieurs comptes avec la même adresse.
  """

  use Portfolio.DataCase, async: true

  alias Portfolio.Auth
  alias Portfolio.Repo

  describe "Gmail normalization prevents duplicate accounts" do
    test "creating user with john.doe@gmail.com normalizes to johndoe@gmail.com" do
      {:ok, user} =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "john.doe@gmail.com", role: :admin})
        |> Repo.insert()

      # L'email stocké doit être normalisé
      assert user.email == "johndoe@gmail.com"
    end

    test "cannot create duplicate user with different dot placement" do
      # Créer l'utilisateur initial
      %Auth.User{}
      |> Auth.User.changeset(%{email: "john.doe@gmail.com", role: :admin})
      |> Repo.insert!()

      # Tenter de créer avec une autre variation (j.o.h.n.doe@gmail.com)
      result =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "j.o.h.n.doe@gmail.com", role: :admin})
        |> Repo.insert()

      # Doit échouer avec une erreur de contrainte unique
      assert {:error, changeset} = result
      assert "has already been taken" in errors_on(changeset).email
    end

    test "can create users with same local part on different domains" do
      # Créer john.doe@gmail.com
      {:ok, user1} =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "john.doe@gmail.com", role: :admin})
        |> Repo.insert()

      # Créer john.doe@yahoo.com (pas de normalisation des points)
      {:ok, user2} =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "john.doe@yahoo.com", role: :admin})
        |> Repo.insert()

      assert user1.email == "johndoe@gmail.com"
      assert user2.email == "john.doe@yahoo.com"
      assert user1.id != user2.id
    end

    test "gmail plus addressing is preserved" do
      {:ok, user} =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "john.doe+work@gmail.com", role: :admin})
        |> Repo.insert()

      # Les points sont supprimés mais le +tag est préservé
      assert user.email == "johndoe+work@gmail.com"
    end

    test "googlemail.com is also normalized" do
      {:ok, user} =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "john.doe@googlemail.com", role: :admin})
        |> Repo.insert()

      # Googlemail doit aussi être normalisé
      assert user.email == "johndoe@googlemail.com"
    end
  end

  describe "Magic link request with Gmail normalization" do
    test "requesting magic link with dots finds existing user" do
      # Créer un utilisateur avec l'email normalisé
      user =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "johndoe@gmail.com", role: :admin})
        |> Repo.insert!()

      # Demander un magic link avec une variante (john.doe@gmail.com)
      assert {:ok, magic_link} = Auth.request_magic_link("john.doe@gmail.com")

      # Le magic link doit être associé au bon utilisateur
      assert magic_link.user_id == user.id
    end

    test "requesting magic link normalizes before lookup" do
      # Créer un utilisateur
      user =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "j.o.h.n.d.o.e@gmail.com", role: :admin})
        |> Repo.insert!()

      # L'email stocké est normalisé
      assert user.email == "johndoe@gmail.com"

      # Demander avec une autre variante
      assert {:ok, magic_link} = Auth.request_magic_link("John.Doe@Gmail.Com")
      assert magic_link.user_id == user.id
    end
  end

  describe "User lookup with Gmail normalization" do
    test "get_user_by_email normalizes before lookup" do
      # Créer un utilisateur
      user =
        %Auth.User{}
        |> Auth.User.changeset(%{email: "john.doe@gmail.com", role: :admin})
        |> Repo.insert!()

      # Rechercher avec différentes variantes
      assert {:ok, found1} = Auth.get_user_by_email("john.doe@gmail.com")
      assert {:ok, found2} = Auth.get_user_by_email("johndoe@gmail.com")
      assert {:ok, found3} = Auth.get_user_by_email("j.o.h.n.d.o.e@gmail.com")
      assert {:ok, found4} = Auth.get_user_by_email("JOHN.DOE@GMAIL.COM")

      # Tous doivent trouver le même utilisateur
      assert found1.id == user.id
      assert found2.id == user.id
      assert found3.id == user.id
      assert found4.id == user.id
    end
  end
end
