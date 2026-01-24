defmodule Portfolio.Auth.MailerTest do
  use Portfolio.DataCase, async: true

  import Swoosh.TestAssertions

  alias Portfolio.Auth.{MagicLink, Mailer, User}

  describe "send_magic_link_email/2" do
    setup do
      user = %User{
        id: Ecto.UUID.generate(),
        email: "test@example.com",
        name: "Test User",
        role: :user
      }

      magic_link = %MagicLink{
        id: Ecto.UUID.generate(),
        user_id: user.id,
        token: Base.encode64(:crypto.strong_rand_bytes(32)),
        short_code: "ABC123",
        expires_at: DateTime.utc_now() |> DateTime.add(900, :second),
        used_at: nil,
        inserted_at: DateTime.utc_now()
      }

      {:ok, user: user, magic_link: magic_link}
    end

    test "sends email with correct recipient", %{user: user, magic_link: magic_link} do
      {:ok, _} = Mailer.send_magic_link_email(user, magic_link)

      assert_email_sent(to: [{user.name, user.email}])
    end

    test "sends email with correct subject", %{user: user, magic_link: magic_link} do
      {:ok, _} = Mailer.send_magic_link_email(user, magic_link)

      assert_email_sent(subject: "Votre lien de connexion")
    end

    test "sends email from correct sender", %{user: user, magic_link: magic_link} do
      {:ok, _} = Mailer.send_magic_link_email(user, magic_link)

      assert_email_sent(from: {"Portfolio Admin", "noreply@portfolio.local"})
    end

    test "includes magic link URL with short_code in body", %{user: user, magic_link: magic_link} do
      {:ok, _} = Mailer.send_magic_link_email(user, magic_link)

      assert_email_sent(fn email ->
        assert email.html_body =~ magic_link.short_code
        assert email.text_body =~ magic_link.short_code
        assert email.html_body =~ "/auth/verify?code=#{magic_link.short_code}"
      end)
    end

    test "includes user name in greeting", %{user: user, magic_link: magic_link} do
      {:ok, _} = Mailer.send_magic_link_email(user, magic_link)

      assert_email_sent(fn email ->
        assert email.html_body =~ "Bonjour #{user.name}"
        assert email.text_body =~ "Bonjour #{user.name}"
      end)
    end

    test "falls back to email when user has no name", %{magic_link: magic_link} do
      user_without_name = %User{
        id: Ecto.UUID.generate(),
        email: "noname@example.com",
        name: nil,
        role: :user
      }

      {:ok, _} = Mailer.send_magic_link_email(user_without_name, magic_link)

      assert_email_sent(fn email ->
        assert email.html_body =~ "Bonjour noname@example.com"
      end)
    end

    test "includes both HTML and text versions", %{user: user, magic_link: magic_link} do
      {:ok, _} = Mailer.send_magic_link_email(user, magic_link)

      assert_email_sent(fn email ->
        assert email.html_body != nil
        assert email.text_body != nil
        assert String.length(email.html_body) > 0
        assert String.length(email.text_body) > 0
      end)
    end

    test "includes security notice about link validity", %{user: user, magic_link: magic_link} do
      {:ok, _} = Mailer.send_magic_link_email(user, magic_link)

      assert_email_sent(fn email ->
        assert email.html_body =~ "15 minutes"
        assert email.text_body =~ "15 minutes"
      end)
    end
  end
end
