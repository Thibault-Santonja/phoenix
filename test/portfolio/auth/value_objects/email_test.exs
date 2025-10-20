defmodule Portfolio.Auth.ValueObjects.EmailTest do
  use ExUnit.Case, async: true

  alias Portfolio.Auth.ValueObjects.Email

  describe "new/1" do
    test "creates valid email" do
      assert {:ok, email} = Email.new("user@example.com")
      assert Email.to_string(email) == "user@example.com"
    end

    test "normalizes to lowercase" do
      assert {:ok, email} = Email.new("USER@EXAMPLE.COM")
      assert Email.to_string(email) == "user@example.com"
    end

    test "trims whitespace" do
      assert {:ok, email} = Email.new("  user@example.com  ")
      assert Email.to_string(email) == "user@example.com"
    end

    test "accepts email with dots in local part" do
      assert {:ok, email} = Email.new("first.last@example.com")
      assert Email.to_string(email) == "first.last@example.com"
    end

    test "accepts email with plus sign" do
      assert {:ok, email} = Email.new("user+tag@example.com")
      assert Email.to_string(email) == "user+tag@example.com"
    end

    test "accepts email with subdomain" do
      assert {:ok, email} = Email.new("user@mail.example.com")
      assert Email.to_string(email) == "user@mail.example.com"
    end

    test "accepts email with hyphen in domain" do
      assert {:ok, email} = Email.new("user@my-domain.com")
      assert Email.to_string(email) == "user@my-domain.com"
    end

    test "accepts email with numbers" do
      assert {:ok, email} = Email.new("user123@example456.com")
      assert Email.to_string(email) == "user123@example456.com"
    end

    test "rejects email without @" do
      assert {:error, :invalid_email} = Email.new("userexample.com")
    end

    test "rejects email without domain" do
      assert {:error, :invalid_email} = Email.new("user@")
    end

    test "rejects email without local part" do
      assert {:error, :invalid_email} = Email.new("@example.com")
    end

    test "rejects email with spaces" do
      assert {:error, :invalid_email} = Email.new("user name@example.com")
    end

    test "rejects email with multiple @" do
      assert {:error, :invalid_email} = Email.new("user@@example.com")
    end

    test "rejects empty string" do
      assert {:error, :invalid_email} = Email.new("")
    end

    test "rejects plain text" do
      assert {:error, :invalid_email} = Email.new("not an email")
    end

    test "rejects too long email" do
      # RFC 5322 limite à 254 caractères
      local = String.duplicate("a", 250)
      long_email = "#{local}@example.com"
      assert {:error, :too_long} = Email.new(long_email)
    end

    test "accepts email at max length" do
      # 254 caractères exactement
      local = String.duplicate("a", 240)
      email_str = "#{local}@ex.co"
      assert {:ok, _email} = Email.new(email_str)
    end
  end

  describe "new!/1" do
    test "returns email struct on success" do
      email = Email.new!("user@example.com")
      assert %Email{value: "user@example.com"} = email
    end

    test "raises ArgumentError on invalid email" do
      assert_raise ArgumentError, "Invalid email: invalid_email", fn ->
        Email.new!("invalid")
      end
    end

    test "raises ArgumentError on too long email" do
      long_email = String.duplicate("a", 250) <> "@example.com"

      assert_raise ArgumentError, "Invalid email: too_long", fn ->
        Email.new!(long_email)
      end
    end
  end

  describe "to_string/1" do
    test "extracts the string value" do
      {:ok, email} = Email.new("user@example.com")
      assert Email.to_string(email) == "user@example.com"
    end
  end

  describe "equal?/2" do
    test "returns true for identical emails" do
      {:ok, email1} = Email.new("user@example.com")
      {:ok, email2} = Email.new("user@example.com")
      assert Email.equal?(email1, email2)
    end

    test "returns false for different emails" do
      {:ok, email1} = Email.new("user1@example.com")
      {:ok, email2} = Email.new("user2@example.com")
      refute Email.equal?(email1, email2)
    end

    test "compares by value after normalization" do
      {:ok, email1} = Email.new("user@example.com")
      {:ok, email2} = Email.new("USER@EXAMPLE.COM")
      assert Email.equal?(email1, email2)
    end
  end

  describe "String.Chars protocol" do
    test "converts email to string automatically" do
      {:ok, email} = Email.new("user@example.com")
      assert "#{email}" == "user@example.com"
    end

    test "works with string interpolation" do
      {:ok, email} = Email.new("admin@example.com")
      assert "Email: #{email}" == "Email: admin@example.com"
    end
  end
end
