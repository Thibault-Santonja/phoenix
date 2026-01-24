defmodule Portfolio.Auth.EmailValidationServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Auth.EmailValidationService
  alias Portfolio.Auth.User

  describe "valid?/1" do
    test "returns {:ok, email} for valid email" do
      assert {:ok, "user@gmail.com"} = EmailValidationService.valid?("user@gmail.com")
    end

    test "normalizes email to lowercase" do
      assert {:ok, "user@gmail.com"} = EmailValidationService.valid?("USER@GMAIL.COM")
    end

    test "trims whitespace" do
      assert {:ok, "user@gmail.com"} = EmailValidationService.valid?("  user@gmail.com  ")
    end

    test "returns error for nil" do
      assert {:error, :required} = EmailValidationService.valid?(nil)
    end

    test "returns error for empty string" do
      assert {:error, :required} = EmailValidationService.valid?("")
    end

    test "returns error for whitespace only (becomes empty after trim, fails format)" do
      # After trim, "   " becomes "", which fails format validation (no @)
      assert {:error, :invalid_format} = EmailValidationService.valid?("   ")
    end

    test "returns error for email without @" do
      assert {:error, :invalid_format} = EmailValidationService.valid?("userexample.com")
    end

    test "returns error for email longer than 320 chars" do
      # 320 is the max, so 321 chars should fail
      long_local = String.duplicate("a", 310)
      long_email = "#{long_local}@example.com"
      # Verify email is actually > 320 chars
      assert String.length(long_email) > 320
      assert {:error, :too_long} = EmailValidationService.valid?(long_email)
    end

    test "returns error for disposable email domain" do
      assert {:error, :disposable_email} = EmailValidationService.valid?("test@mailinator.com")
    end

    test "returns error for disposable email subdomain" do
      assert {:error, :disposable_email} =
               EmailValidationService.valid?("test@sub.mailinator.com")
    end
  end

  describe "disposable?/1" do
    test "returns true for known disposable domains" do
      assert EmailValidationService.disposable?("user@mailinator.com")
      assert EmailValidationService.disposable?("user@guerrillamail.com")
      assert EmailValidationService.disposable?("user@temp-mail.org")
      assert EmailValidationService.disposable?("user@yopmail.com")
    end

    test "returns false for legitimate email providers" do
      refute EmailValidationService.disposable?("user@gmail.com")
      refute EmailValidationService.disposable?("user@outlook.com")
      refute EmailValidationService.disposable?("user@yahoo.com")
      refute EmailValidationService.disposable?("user@protonmail.com")
    end

    test "returns false for nil" do
      refute EmailValidationService.disposable?(nil)
    end

    test "returns false for empty string" do
      refute EmailValidationService.disposable?("")
    end

    test "detects subdomains of disposable domains" do
      assert EmailValidationService.disposable?("user@sub.mailinator.com")
      assert EmailValidationService.disposable?("user@test.guerrillamail.com")
    end
  end

  describe "valid_mx?/1" do
    @tag :network
    test "returns true for domains with valid MX records" do
      # Gmail has MX records
      assert EmailValidationService.valid_mx?("test@gmail.com")
    end

    test "returns false for nil" do
      refute EmailValidationService.valid_mx?(nil)
    end

    test "returns false for empty string" do
      refute EmailValidationService.valid_mx?("")
    end

    # Note: MX validation is skipped in test environment by default
    # These tests verify the behavior when skip_mx_validation is true
    test "skips MX validation when configured" do
      # In test env, MX validation is typically skipped
      # This should return true without making actual DNS queries
      assert EmailValidationService.valid_mx?("test@any-domain.test")
    end
  end

  describe "validate_email/1 with User schema" do
    test "validates required email" do
      changeset =
        %User{}
        |> Ecto.Changeset.cast(%{}, [:email])
        |> EmailValidationService.validate_email()

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email length" do
      long_email = String.duplicate("a", 321)

      changeset =
        %User{}
        |> Ecto.Changeset.cast(%{email: long_email}, [:email])
        |> EmailValidationService.validate_email()

      errors = errors_on(changeset)
      assert Map.has_key?(errors, :email)
    end

    test "validates disposable email" do
      changeset =
        %User{}
        |> Ecto.Changeset.cast(%{email: "test@mailinator.com"}, [:email])
        |> EmailValidationService.validate_email()

      assert %{email: ["les adresses email temporaires ne sont pas autorisées"]} =
               errors_on(changeset)
    end

    test "passes for valid email" do
      changeset =
        %User{}
        |> Ecto.Changeset.cast(%{email: "unique-test-user@gmail.com"}, [:email])
        |> EmailValidationService.validate_email()

      errors = errors_on(changeset)
      # Should not have disposable email error
      refute errors[:email] == ["les adresses email temporaires ne sont pas autorisées"]
    end
  end

  describe "validate_email_format/1" do
    test "validates without unique constraint check" do
      changeset =
        %User{}
        |> Ecto.Changeset.cast(%{email: "valid@gmail.com"}, [:email])
        |> EmailValidationService.validate_email_format()

      assert changeset.valid?
    end

    test "rejects disposable email" do
      changeset =
        %User{}
        |> Ecto.Changeset.cast(%{email: "test@10minutemail.com"}, [:email])
        |> EmailValidationService.validate_email_format()

      refute changeset.valid?
    end

    test "validates required field" do
      changeset =
        %User{}
        |> Ecto.Changeset.cast(%{}, [:email])
        |> EmailValidationService.validate_email_format()

      refute changeset.valid?
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates max length" do
      long_email = String.duplicate("a", 321)

      changeset =
        %User{}
        |> Ecto.Changeset.cast(%{email: long_email}, [:email])
        |> EmailValidationService.validate_email_format()

      refute changeset.valid?
    end
  end

  describe "error_message/1" do
    test "returns correct message for :required" do
      assert EmailValidationService.error_message(:required) == "est requis"
    end

    test "returns correct message for :too_long" do
      assert EmailValidationService.error_message(:too_long) =~ "trop long"
    end

    test "returns correct message for :invalid_format" do
      assert EmailValidationService.error_message(:invalid_format) == "format invalide"
    end

    test "returns correct message for :disposable_email" do
      assert EmailValidationService.error_message(:disposable_email) =~
               "temporaires ne sont pas autorisées"
    end

    test "returns correct message for :invalid_mx" do
      assert EmailValidationService.error_message(:invalid_mx) =~ "ne peut pas recevoir"
    end
  end

  describe "edge cases" do
    test "handles email with plus sign" do
      assert {:ok, "user+tag@gmail.com"} = EmailValidationService.valid?("user+tag@gmail.com")
    end

    test "handles email with dots" do
      assert {:ok, "user.name@gmail.com"} = EmailValidationService.valid?("user.name@gmail.com")
    end

    test "handles email with numbers" do
      assert {:ok, "user123@gmail.com"} = EmailValidationService.valid?("user123@gmail.com")
    end

    test "handles email with hyphen in domain" do
      assert {:ok, "user@my-domain.com"} = EmailValidationService.valid?("user@my-domain.com")
    end

    test "handles email with subdomain" do
      assert {:ok, "user@mail.example.com"} =
               EmailValidationService.valid?("user@mail.example.com")
    end
  end
end
