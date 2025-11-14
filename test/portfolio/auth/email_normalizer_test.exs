defmodule Portfolio.Auth.EmailNormalizerTest do
  @moduledoc """
  Tests pour la normalisation des adresses email.

  Couvre notamment la normalisation Gmail (ignorer les points) et
  d'autres règles spécifiques aux fournisseurs.
  """

  use ExUnit.Case, async: true

  alias Portfolio.Auth.EmailNormalizer

  describe "normalize/1" do
    test "converts email to lowercase" do
      assert EmailNormalizer.normalize("John.Doe@EXAMPLE.COM") == "john.doe@example.com"
    end

    test "trims whitespace" do
      assert EmailNormalizer.normalize("  user@example.com  ") == "user@example.com"
    end

    test "handles empty string" do
      assert EmailNormalizer.normalize("") == ""
    end

    test "handles nil" do
      assert EmailNormalizer.normalize(nil) == nil
    end
  end

  describe "normalize/1 with Gmail" do
    test "removes dots from Gmail local part" do
      assert EmailNormalizer.normalize("john.doe@gmail.com") == "johndoe@gmail.com"
    end

    test "removes multiple dots from Gmail" do
      assert EmailNormalizer.normalize("j.o.h.n.d.o.e@gmail.com") == "johndoe@gmail.com"
    end

    test "preserves dots in non-Gmail addresses" do
      assert EmailNormalizer.normalize("john.doe@example.com") == "john.doe@example.com"
    end

    test "handles Gmail with uppercase" do
      assert EmailNormalizer.normalize("John.Doe@Gmail.Com") == "johndoe@gmail.com"
    end

    test "handles googlemail.com domain (Gmail alias)" do
      assert EmailNormalizer.normalize("john.doe@googlemail.com") == "johndoe@googlemail.com"
    end

    test "removes dots but preserves plus addressing" do
      # Gmail supporte aussi le + pour les alias
      # user+tag@gmail.com devrait normaliser la partie avant le +
      assert EmailNormalizer.normalize("john.doe+work@gmail.com") == "johndoe+work@gmail.com"
    end

    test "handles edge case with consecutive dots" do
      assert EmailNormalizer.normalize("john..doe@gmail.com") == "johndoe@gmail.com"
    end

    test "handles dot at start or end" do
      assert EmailNormalizer.normalize(".john.doe.@gmail.com") == "johndoe@gmail.com"
    end
  end

  describe "normalize/1 with other domains" do
    test "preserves Yahoo email as-is" do
      assert EmailNormalizer.normalize("john.doe@yahoo.com") == "john.doe@yahoo.com"
    end

    test "preserves Outlook email as-is" do
      assert EmailNormalizer.normalize("john.doe@outlook.com") == "john.doe@outlook.com"
    end

    test "preserves Hotmail email as-is" do
      assert EmailNormalizer.normalize("john.doe@hotmail.com") == "john.doe@hotmail.com"
    end

    test "preserves corporate email as-is" do
      assert EmailNormalizer.normalize("john.doe@company.com") == "john.doe@company.com"
    end
  end

  describe "gmail_domain?/1" do
    test "returns true for gmail.com" do
      assert EmailNormalizer.gmail_domain?("gmail.com") == true
    end

    test "returns true for googlemail.com" do
      assert EmailNormalizer.gmail_domain?("googlemail.com") == true
    end

    test "returns false for other domains" do
      assert EmailNormalizer.gmail_domain?("yahoo.com") == false
      assert EmailNormalizer.gmail_domain?("example.com") == false
    end

    test "is case insensitive" do
      assert EmailNormalizer.gmail_domain?("Gmail.Com") == true
      assert EmailNormalizer.gmail_domain?("GOOGLEMAIL.COM") == true
    end
  end
end
