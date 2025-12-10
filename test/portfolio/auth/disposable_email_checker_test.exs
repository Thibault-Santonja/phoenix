defmodule Portfolio.Auth.DisposableEmailCheckerTest do
  @moduledoc """
  Tests pour la détection des emails jetables/temporaires.
  """

  use ExUnit.Case, async: true

  alias Portfolio.Auth.DisposableEmailChecker

  doctest DisposableEmailChecker

  describe "disposable?/1" do
    test "returns true for known disposable email domains" do
      assert DisposableEmailChecker.disposable?("user@10minutemail.com") == true
      assert DisposableEmailChecker.disposable?("user@guerrillamail.com") == true
      assert DisposableEmailChecker.disposable?("user@mailinator.com") == true
      assert DisposableEmailChecker.disposable?("user@temp-mail.org") == true
      assert DisposableEmailChecker.disposable?("user@throwaway.email") == true
    end

    test "returns false for legitimate email domains" do
      assert DisposableEmailChecker.disposable?("user@gmail.com") == false
      assert DisposableEmailChecker.disposable?("user@yahoo.com") == false
      assert DisposableEmailChecker.disposable?("user@outlook.com") == false
      assert DisposableEmailChecker.disposable?("user@company.com") == false
    end

    test "is case insensitive" do
      assert DisposableEmailChecker.disposable?("user@MAILINATOR.COM") == true
      assert DisposableEmailChecker.disposable?("user@Mailinator.Com") == true
      assert DisposableEmailChecker.disposable?("USER@mailinator.com") == true
    end

    test "handles emails with subdomains" do
      assert DisposableEmailChecker.disposable?("user@subdomain.mailinator.com") == true
    end

    test "returns false for nil" do
      assert DisposableEmailChecker.disposable?(nil) == false
    end

    test "returns false for empty string" do
      assert DisposableEmailChecker.disposable?("") == false
    end

    test "returns false for invalid email format" do
      assert DisposableEmailChecker.disposable?("not-an-email") == false
    end
  end

  describe "extract_domain/1" do
    test "extracts domain from email" do
      assert DisposableEmailChecker.extract_domain("user@example.com") == "example.com"
    end

    test "handles email with subdomain" do
      assert DisposableEmailChecker.extract_domain("user@mail.example.com") == "mail.example.com"
    end

    test "is case insensitive" do
      assert DisposableEmailChecker.extract_domain("USER@EXAMPLE.COM") == "example.com"
    end

    test "returns nil for invalid email" do
      assert DisposableEmailChecker.extract_domain("invalid") == nil
      assert DisposableEmailChecker.extract_domain("") == nil
      assert DisposableEmailChecker.extract_domain(nil) == nil
    end
  end

  describe "disposable_domains/0" do
    test "returns a list of disposable domains" do
      domains = DisposableEmailChecker.disposable_domains()
      assert is_list(domains)
      assert length(domains) > 0
      assert "mailinator.com" in domains
      assert "guerrillamail.com" in domains
    end

    test "all domains are lowercase" do
      domains = DisposableEmailChecker.disposable_domains()
      assert Enum.all?(domains, fn domain -> domain == String.downcase(domain) end)
    end
  end
end
