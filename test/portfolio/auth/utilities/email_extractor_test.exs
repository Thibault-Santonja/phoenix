defmodule Portfolio.Auth.Utilities.EmailExtractorTest do
  use ExUnit.Case, async: true

  alias Portfolio.Auth.Utilities.EmailExtractor

  describe "extract_domain/1" do
    test "extracts domain from valid email" do
      assert EmailExtractor.extract_domain("user@example.com") == "example.com"
    end

    test "extracts domain from email with subdomain" do
      assert EmailExtractor.extract_domain("user@sub.example.com") == "sub.example.com"
    end

    test "normalizes domain to lowercase" do
      assert EmailExtractor.extract_domain("USER@EXAMPLE.COM") == "example.com"
      assert EmailExtractor.extract_domain("user@EXAMPLE.COM") == "example.com"
      assert EmailExtractor.extract_domain("user@Example.Com") == "example.com"
    end

    test "handles email with plus addressing" do
      assert EmailExtractor.extract_domain("user+tag@example.com") == "example.com"
    end

    test "handles email with dots in local part" do
      assert EmailExtractor.extract_domain("first.last@example.com") == "example.com"
    end

    test "returns nil for nil input" do
      assert EmailExtractor.extract_domain(nil) == nil
    end

    test "returns nil for empty string" do
      assert EmailExtractor.extract_domain("") == nil
    end

    test "returns nil for email without @" do
      assert EmailExtractor.extract_domain("invalid-email") == nil
    end

    test "returns nil for email with empty domain" do
      assert EmailExtractor.extract_domain("user@") == nil
    end

    test "returns nil for email with multiple @ symbols" do
      # String.split with "@" will produce more than 2 parts
      assert EmailExtractor.extract_domain("user@@example.com") == nil
      assert EmailExtractor.extract_domain("user@foo@example.com") == nil
    end

    test "handles email with just @" do
      assert EmailExtractor.extract_domain("@") == nil
    end

    test "handles email with only domain part missing local" do
      # "@example.com" splits into ["", "example.com"]
      assert EmailExtractor.extract_domain("@example.com") == "example.com"
    end
  end

  describe "valid_domain?/1" do
    test "returns true for valid email" do
      assert EmailExtractor.valid_domain?("user@example.com") == true
    end

    test "returns true for email with subdomain" do
      assert EmailExtractor.valid_domain?("user@sub.example.com") == true
    end

    test "returns false for nil" do
      assert EmailExtractor.valid_domain?(nil) == false
    end

    test "returns false for empty string" do
      assert EmailExtractor.valid_domain?("") == false
    end

    test "returns false for invalid email without @" do
      assert EmailExtractor.valid_domain?("invalid") == false
    end

    test "returns false for email with empty domain" do
      assert EmailExtractor.valid_domain?("user@") == false
    end
  end
end
