defmodule Portfolio.Auth.UserTest do
  use Portfolio.DataCase

  alias Portfolio.Auth.User

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", role: "admin"})
      assert changeset.valid?
    end

    test "requires email" do
      changeset = User.changeset(%User{}, %{role: "admin"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end

    test "requires role" do
      changeset = User.changeset(%User{}, %{email: "test@example.com"})
      # Role a une valeur par défaut "admin" dans le schéma, donc le changeset est valide
      # mais si on passe explicitement role: nil, ça devrait être invalide
      changeset_nil = User.changeset(%User{}, %{email: "test@example.com", role: nil})
      refute changeset_nil.valid?
      assert "can't be blank" in errors_on(changeset_nil).role
    end

    test "validates email format" do
      invalid_emails = [
        "notanemail",
        "@example.com",
        "test@",
        "test @example.com",
        "test@example .com"
      ]

      for invalid_email <- invalid_emails do
        changeset = User.changeset(%User{}, %{email: invalid_email, role: "admin"})
        refute changeset.valid?
        assert "doit être une adresse email valide" in errors_on(changeset).email
      end
    end

    test "validates email max length" do
      long_email = String.duplicate("a", 150) <> "@example.com"
      changeset = User.changeset(%User{}, %{email: long_email, role: "admin"})
      refute changeset.valid?
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates role inclusion" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", role: "user"})
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).role
    end

    test "accepts admin role" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", role: "admin"})
      assert changeset.valid?
    end

    test "accepts superadmin role" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", role: "superadmin"})
      assert changeset.valid?
    end

    test "checks email uniqueness constraint" do
      _user = insert_user(email: "test@example.com")

      changeset = User.changeset(%User{}, %{email: "test@example.com", role: "admin"})
      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).email
    end

    test "accepts optional name field" do
      changeset =
        User.changeset(%User{}, %{email: "test@example.com", role: "admin", name: "Test User"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "Test User"
    end
  end

  describe "registration_changeset/2" do
    test "valid registration with email only" do
      changeset = User.registration_changeset(%User{}, %{email: "test@example.com"})
      assert changeset.valid?
      # put_change force la valeur, donc on doit vérifier avec apply_changes
      user = Ecto.Changeset.apply_changes(changeset)
      assert user.role == "admin"
    end

    test "requires email for registration" do
      changeset = User.registration_changeset(%User{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end

    test "validates email format on registration" do
      changeset = User.registration_changeset(%User{}, %{email: "invalid"})
      refute changeset.valid?
      assert "doit être une adresse email valide" in errors_on(changeset).email
    end

    test "automatically sets role to admin" do
      changeset = User.registration_changeset(%User{}, %{email: "test@example.com"})
      user = Ecto.Changeset.apply_changes(changeset)
      assert user.role == "admin"
    end

    test "accepts optional name on registration" do
      changeset =
        User.registration_changeset(%User{}, %{email: "test@example.com", name: "John Doe"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "John Doe"
    end

    test "checks email uniqueness on registration" do
      insert_user(email: "test@example.com")

      changeset = User.registration_changeset(%User{}, %{email: "test@example.com"})
      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).email
    end

    test "prevents SQL injection in email field" do
      malicious_email = "'; DROP TABLE users; --@example.com"
      changeset = User.registration_changeset(%User{}, %{email: malicious_email})
      # Should fail validation, not cause SQL injection
      refute changeset.valid?
    end

    test "prevents XSS in name field" do
      xss_name = "<script>alert('xss')</script>"

      changeset =
        User.registration_changeset(%User{}, %{email: "test@example.com", name: xss_name})

      # Changeset should be valid (sanitization happens at view layer), but data should be stored as-is
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == xss_name
    end
  end

  describe "profile_changeset/2" do
    test "allows updating name" do
      user = insert_user()
      changeset = User.profile_changeset(user, %{name: "New Name"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "New Name"
    end

    test "validates name min length" do
      user = insert_user()
      changeset = User.profile_changeset(user, %{name: "A"})
      refute changeset.valid?
      assert "should be at least 2 character(s)" in errors_on(changeset).name
    end

    test "validates name max length" do
      user = insert_user()
      long_name = String.duplicate("a", 101)
      changeset = User.profile_changeset(user, %{name: long_name})
      refute changeset.valid?
      assert "should be at most 100 character(s)" in errors_on(changeset).name
    end

    test "allows nil name" do
      user = insert_user()
      changeset = User.profile_changeset(user, %{name: nil})
      assert changeset.valid?
    end

    test "ignores email changes" do
      user = insert_user(email: "original@example.com")
      changeset = User.profile_changeset(user, %{email: "changed@example.com", name: "Test"})

      # Email should not be in changes
      refute Map.has_key?(changeset.changes, :email)
    end

    test "ignores role changes" do
      user = insert_user(role: "admin")
      changeset = User.profile_changeset(user, %{role: "superadmin", name: "Test"})

      # Role should not be in changes
      refute Map.has_key?(changeset.changes, :role)
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
end
