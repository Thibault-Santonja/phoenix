defmodule Portfolio.Auth.EmailTypeTest do
  use ExUnit.Case, async: true

  alias Portfolio.Auth.EmailType

  describe "type/0" do
    test "returns :string as the underlying database type" do
      assert EmailType.type() == :string
    end
  end

  describe "cast/1" do
    test "casts valid email with lowercase normalization" do
      assert {:ok, "user@example.com"} = EmailType.cast("USER@EXAMPLE.COM")
    end

    test "casts valid email with whitespace trimming" do
      assert {:ok, "user@example.com"} = EmailType.cast("  user@example.com  ")
    end

    test "casts valid email with both normalization and trimming" do
      assert {:ok, "user@example.com"} = EmailType.cast("  USER@EXAMPLE.COM  ")
    end

    test "casts already normalized email" do
      assert {:ok, "user@example.com"} = EmailType.cast("user@example.com")
    end

    test "casts email with subdomain" do
      assert {:ok, "user@mail.example.com"} = EmailType.cast("user@mail.example.com")
    end

    test "casts email with plus addressing" do
      assert {:ok, "user+tag@example.com"} = EmailType.cast("user+tag@example.com")
    end

    test "casts email with dots in local part" do
      assert {:ok, "first.last@example.com"} = EmailType.cast("first.last@example.com")
    end

    test "casts email with numbers" do
      assert {:ok, "user123@example.com"} = EmailType.cast("user123@example.com")
    end

    test "casts email with hyphen in domain" do
      assert {:ok, "user@my-domain.com"} = EmailType.cast("user@my-domain.com")
    end

    test "returns error for nil" do
      assert :error = EmailType.cast(nil)
    end

    test "returns error for empty string" do
      assert :error = EmailType.cast("")
    end

    test "returns error for whitespace only" do
      assert :error = EmailType.cast("   ")
    end

    test "returns error for missing @ symbol" do
      assert :error = EmailType.cast("userexample.com")
    end

    test "returns error for multiple @ symbols" do
      assert :error = EmailType.cast("user@@example.com")
    end

    test "returns error for missing local part" do
      assert :error = EmailType.cast("@example.com")
    end

    test "returns error for missing domain" do
      assert :error = EmailType.cast("user@")
    end

    test "returns error for missing TLD" do
      assert :error = EmailType.cast("user@example")
    end

    test "returns error for invalid characters in local part" do
      assert :error = EmailType.cast("user name@example.com")
    end

    test "returns error for invalid characters in domain" do
      assert :error = EmailType.cast("user@exam ple.com")
    end

    test "returns error for email starting with dot" do
      assert :error = EmailType.cast(".user@example.com")
    end

    test "returns error for email ending with dot before @" do
      assert :error = EmailType.cast("user.@example.com")
    end

    test "returns error for consecutive dots in local part" do
      assert :error = EmailType.cast("user..name@example.com")
    end

    test "returns error for domain starting with hyphen" do
      assert :error = EmailType.cast("user@-example.com")
    end

    test "returns error for domain ending with hyphen" do
      assert :error = EmailType.cast("user@example-.com")
    end

    test "returns error for non-string input" do
      assert :error = EmailType.cast(123)
      assert :error = EmailType.cast(%{email: "user@example.com"})
      assert :error = EmailType.cast(["user@example.com"])
    end

    test "returns error for email exceeding maximum length" do
      # RFC 5321: max 320 characters (64 local + @ + 255 domain)
      local = String.duplicate("a", 65)
      domain = String.duplicate("a", 250) <> ".com"
      assert :error = EmailType.cast("#{local}@#{domain}")
    end

    test "accepts email at maximum valid length" do
      # RFC 5321: max 320 chars (64 local + @ + 255 domain)
      # RFC 1035: each domain label max 63 chars
      # Our regex allows labels up to 61 chars for compatibility
      local = String.duplicate("a", 64)
      # Create domain with labels of 50 chars each for safe validation
      label = String.duplicate("a", 50)
      domain = "#{label}.#{label}.#{label}.example.com"
      email = "#{local}@#{domain}"
      assert {:ok, ^email} = EmailType.cast(email)
    end

    test "returns error for very short domain" do
      assert :error = EmailType.cast("user@a.b")
    end

    test "accepts minimum valid domain length" do
      assert {:ok, "user@ab.co"} = EmailType.cast("user@ab.co")
    end
  end

  describe "load/1" do
    test "loads valid email from database" do
      assert {:ok, "user@example.com"} = EmailType.load("user@example.com")
    end

    test "loads email without additional normalization" do
      # Assumes data in DB is already normalized
      assert {:ok, "user@example.com"} = EmailType.load("user@example.com")
    end

    test "returns error for nil" do
      assert :error = EmailType.load(nil)
    end

    test "returns error for non-string" do
      assert :error = EmailType.load(123)
    end
  end

  describe "dump/1" do
    test "dumps valid email to database" do
      assert {:ok, "user@example.com"} = EmailType.dump("user@example.com")
    end

    test "dumps already normalized email" do
      assert {:ok, "user@example.com"} = EmailType.dump("user@example.com")
    end

    test "returns error for nil" do
      assert :error = EmailType.dump(nil)
    end

    test "returns error for non-string" do
      assert :error = EmailType.dump(123)
    end
  end

  describe "equal?/2" do
    test "returns true for identical emails" do
      assert EmailType.equal?("user@example.com", "user@example.com")
    end

    test "returns true for case-insensitive match" do
      assert EmailType.equal?("user@example.com", "USER@EXAMPLE.COM")
    end

    test "returns true for whitespace-trimmed match" do
      assert EmailType.equal?("user@example.com", "  user@example.com  ")
    end

    test "returns false for different emails" do
      refute EmailType.equal?("user1@example.com", "user2@example.com")
    end

    test "returns false for nil comparison" do
      refute EmailType.equal?("user@example.com", nil)
      refute EmailType.equal?(nil, "user@example.com")
    end
  end

  describe "normalization" do
    test "normalize/1 converts to lowercase" do
      assert "user@example.com" = EmailType.normalize("USER@EXAMPLE.COM")
    end

    test "normalize/1 trims whitespace" do
      assert "user@example.com" = EmailType.normalize("  user@example.com  ")
    end

    test "normalize/1 handles both lowercase and trim" do
      assert "user@example.com" = EmailType.normalize("  USER@EXAMPLE.COM  ")
    end

    test "normalize/1 preserves valid email format" do
      email = "user+tag@mail.example.com"
      assert ^email = EmailType.normalize(email)
    end
  end

  describe "validation" do
    test "valid?/1 returns true for valid email" do
      assert EmailType.valid?("user@example.com")
    end

    test "valid?/1 returns true for complex valid email" do
      assert EmailType.valid?("user+tag@mail.example.com")
    end

    test "valid?/1 returns false for invalid email" do
      refute EmailType.valid?("invalid")
    end

    test "valid?/1 returns false for nil" do
      refute EmailType.valid?(nil)
    end

    test "valid?/1 returns false for empty string" do
      refute EmailType.valid?("")
    end

    test "valid?/1 returns false for missing @" do
      refute EmailType.valid?("userexample.com")
    end

    test "valid?/1 returns false for multiple @" do
      refute EmailType.valid?("user@@example.com")
    end
  end

  describe "integration with Ecto" do
    test "can be used as Ecto.Type" do
      # Verify Ecto.Type callbacks are implemented by calling them directly
      # rather than using function_exported? which may not work with @impl callbacks
      assert EmailType.type() == :string
      assert {:ok, _} = EmailType.cast("test@example.com")
      assert {:ok, _} = EmailType.load("test@example.com")
      assert {:ok, _} = EmailType.dump("test@example.com")
    end

    test "implements optional equal?/2 callback" do
      # Verify equal?/2 works correctly
      assert EmailType.equal?("test@example.com", "test@example.com")
      refute EmailType.equal?("a@example.com", "b@example.com")
    end
  end
end
