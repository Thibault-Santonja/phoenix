defmodule Portfolio.Auth.MagicLinkServiceAdminTest do
  @moduledoc """
  Tests pour les fonctions admin de MagicLinkService.

  Vérifie que les admins peuvent bypasser le rate limiting lors de
  l'envoi de magic links aux utilisateurs.
  """

  use Portfolio.DataCase, async: false

  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Auth.MagicLinkService
  alias Portfolio.Auth.UserService

  describe "request_magic_link_as_admin/1" do
    test "bypasses rate limiting when admin sends magic link" do
      # Use unique email to avoid rate limit collisions with other tests
      unique_email = "user_#{System.unique_integer([:positive])}@example.com"
      user = create_user(email: unique_email)

      # Épuiser le rate limit normal (5 requêtes par heure)
      for _i <- 1..5 do
        {:ok, _} = MagicLinkService.request_magic_link(user.email)
      end

      # La 6ème requête normale devrait échouer
      assert {:error, {:rate_limit_exceeded, _}} =
               MagicLinkService.request_magic_link(user.email)

      # Mais la fonction admin devrait réussir
      assert {:ok, magic_link} = MagicLinkService.request_magic_link_as_admin(user.email)
      assert magic_link.user_id == user.id
      refute magic_link.used_at
    end

    test "creates magic link for existing user" do
      user = create_user(email: "admin@example.com")

      assert {:ok, magic_link} = MagicLinkService.request_magic_link_as_admin(user.email)

      assert magic_link.user_id == user.id
      assert magic_link.token
      assert magic_link.short_code
      assert magic_link.expires_at
      refute magic_link.used_at
    end

    @tag :skip
    test "returns error for non-existent user in production" do
      # NOTE: This test is skipped because Mix.env() cannot be changed at runtime.
      # In production (MIX_ENV=prod), admins get {:error, :user_not_found} for
      # non-existent users, allowing them to distinguish between existing and
      # non-existing users (admins are trusted, unlike public endpoints).
    end

    test "creates user in dev environment" do
      # Vérifier que nous sommes en environnement dev/test
      # Note: Mix.env() returns the current environment (:test when running tests)
      assert Mix.env() in [:dev, :test]

      # Utilisateur n'existe pas encore
      assert {:error, :not_found} =
               UserService.get_user_by_email("newuser@example.com")

      # La fonction admin crée l'utilisateur en dev/test
      assert {:ok, magic_link} =
               MagicLinkService.request_magic_link_as_admin("newuser@example.com")

      assert magic_link.token

      # Vérifier que l'utilisateur a été créé
      assert {:ok, user} = UserService.get_user_by_email("newuser@example.com")
      assert user.email == "newuser@example.com"
    end

    test "uses configuration for magic link TTL" do
      user = create_user(email: "user@example.com")

      # Récupérer la configuration actuelle
      ttl_minutes =
        Application.get_env(:portfolio, :auth, [])
        |> Keyword.get(:magic_link_ttl_minutes, 15)

      assert {:ok, magic_link} = MagicLinkService.request_magic_link_as_admin(user.email)

      # Vérifier que l'expiration est correcte (avec une marge de 1 minute)
      expected_expires_at = DateTime.add(DateTime.utc_now(), ttl_minutes, :minute)
      diff_seconds = DateTime.diff(magic_link.expires_at, expected_expires_at, :second)

      assert abs(diff_seconds) < 60,
             "Expected expiration within 60 seconds, got diff: #{diff_seconds}"
    end

    test "emits domain event when magic link is created" do
      user = create_user(email: "admin@example.com")

      # S'abonner aux événements
      :ok = Portfolio.DomainEvents.subscribe(:magic_link_requested)

      assert {:ok, magic_link} = MagicLinkService.request_magic_link_as_admin(user.email)

      # Vérifier que l'événement a été émis (format sans :domain_event tag)
      assert_receive {:magic_link_requested, event}, 1000

      # Note: token is intentionally NOT included in the event for security reasons
      assert event.magic_link_id == magic_link.id
      assert event.email == user.email
      assert event.short_code == magic_link.short_code
    end

    test "returns valid magic link structure" do
      user = create_user(email: "user@example.com")

      assert {:ok, magic_link} = MagicLinkService.request_magic_link_as_admin(user.email)

      # Vérifier la structure du magic link
      assert magic_link.user_id == user.id
      assert is_binary(magic_link.token)
      assert String.length(magic_link.token) > 20
      assert is_binary(magic_link.short_code)
      assert String.length(magic_link.short_code) == 6
      assert %DateTime{} = magic_link.expires_at
    end
  end
end
