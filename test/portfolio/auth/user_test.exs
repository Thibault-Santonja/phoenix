defmodule Portfolio.Auth.UserTest do
  use Portfolio.DataCase

  alias Portfolio.Auth.User

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", role: :admin})
      assert changeset.valid?
    end

    test "requires email" do
      changeset = User.changeset(%User{}, %{role: :admin})
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

    test "validates email format - accepts valid emails" do
      valid_emails = [
        "user@example.com",
        "user.name@example.com",
        "user+tag@example.com",
        "user_name@example.com",
        "user-name@example.com",
        "user123@example.com",
        "user@subdomain.example.com",
        "user@example.co.uk",
        "user@example-domain.com",
        "first.last@example.com",
        "user+filter@gmail.com",
        "user!test@example.com",
        "user#test@example.com",
        "user$test@example.com"
      ]

      for valid_email <- valid_emails do
        changeset = User.changeset(%User{}, %{email: valid_email, role: :admin})
        assert changeset.valid?, "#{valid_email} should be valid"
      end
    end

    test "validates email format - rejects invalid emails" do
      invalid_emails = [
        "notanemail",
        "@example.com",
        "test@",
        "test @example.com",
        "test@example .com",
        "test@.example.com",
        "test@example..com",
        "test@@example.com",
        " test@example.com",
        "test@example.com ",
        "test@-example.com",
        "test@example-.com"
      ]

      for invalid_email <- invalid_emails do
        changeset = User.changeset(%User{}, %{email: invalid_email, role: :admin})
        refute changeset.valid?, "#{invalid_email} should be invalid"
        assert "doit être une adresse email valide" in errors_on(changeset).email
      end
    end

    test "normalizes email to lowercase" do
      changeset = User.changeset(%User{}, %{email: "Test.User@EXAMPLE.COM", role: :admin})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :email) == "test.user@example.com"
    end

    test "validates email max length" do
      long_email = String.duplicate("a", 150) <> "@example.com"
      changeset = User.changeset(%User{}, %{email: long_email, role: :admin})
      refute changeset.valid?
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates role inclusion" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", role: :invalid_role})
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).role
    end

    test "accepts admin role" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", role: :admin})
      assert changeset.valid?
    end

    test "accepts superadmin role" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", role: :superadmin})
      assert changeset.valid?
    end

    test "checks email uniqueness constraint" do
      _user = insert_user(email: "test@example.com")

      changeset = User.changeset(%User{}, %{email: "test@example.com", role: :admin})
      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).email
    end

    test "accepts optional name field" do
      changeset =
        User.changeset(%User{}, %{email: "test@example.com", role: :admin, name: "Test User"})

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
      assert user.role == :admin
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
      assert user.role == :admin
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
      user = insert_user(role: :admin)
      changeset = User.profile_changeset(user, %{role: :superadmin, name: "Test"})

      # Role should not be in changes
      refute Map.has_key?(changeset.changes, :role)
    end
  end

  describe "admin_changeset/2" do
    test "allows updating role" do
      user = insert_user(role: :admin)
      changeset = User.admin_changeset(user, %{role: :user})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :role) == :user
    end

    test "allows updating name" do
      user = insert_user()
      changeset = User.admin_changeset(user, %{name: "Admin Updated"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "Admin Updated"
    end

    test "allows updating both role and name" do
      user = insert_user(role: :admin)
      changeset = User.admin_changeset(user, %{role: :user, name: "Regular User"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :role) == :user
      assert Ecto.Changeset.get_change(changeset, :name) == "Regular User"
    end

    test "requires role" do
      user = insert_user()
      changeset = User.admin_changeset(user, %{role: nil})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).role
    end

    test "validates role inclusion" do
      user = insert_user()
      changeset = User.admin_changeset(user, %{role: :invalid})
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).role
    end

    test "validates name min length" do
      user = insert_user()
      changeset = User.admin_changeset(user, %{name: "X"})
      refute changeset.valid?
      assert "should be at least 2 character(s)" in errors_on(changeset).name
    end

    test "validates name max length" do
      user = insert_user()
      long_name = String.duplicate("x", 101)
      changeset = User.admin_changeset(user, %{name: long_name})
      refute changeset.valid?
      assert "should be at most 100 character(s)" in errors_on(changeset).name
    end

    test "ignores email changes for security" do
      user = insert_user(email: "original@example.com")
      changeset = User.admin_changeset(user, %{email: "changed@example.com", role: :user})

      # Email should not be in changes
      refute Map.has_key?(changeset.changes, :email)
    end

    test "accepts all valid roles" do
      user = insert_user()

      for role <- [:admin, :superadmin, :user] do
        changeset = User.admin_changeset(user, %{role: role})
        assert changeset.valid?, "Role #{role} should be valid"
      end
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
