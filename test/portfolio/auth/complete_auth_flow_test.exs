defmodule Portfolio.Auth.CompleteAuthFlowTest do
  @moduledoc """
  Happy path tests for complete authentication flow.

  These tests verify the full authentication journey:
  - Request magic link → Email sent
  - Verify token → Session created
  - Access admin pages
  - Logout → Session invalidated
  """

  use Portfolio.DataCase, async: true

  @moduletag :skip

  alias Portfolio.Auth

  import PortfolioTest.Fixtures.AuthFixtures

  describe "complete authentication flow" do
    test "user can request magic link and authenticate" do
      # Arrange: Create user
      email = "user#{System.unique_integer([:positive])}@example.com"
      _user = create_user(email: email)

      # Act: Request magic link
      assert {:ok, magic_link} = Auth.request_magic_link(email)

      # Assert: Magic link created
      assert magic_link.user_id != nil
      assert magic_link.token != nil
      assert magic_link.used_at == nil
      assert magic_link.expires_at != nil

      # Act: Verify magic link
      assert {:ok, verified_user} = Auth.verify_magic_link(magic_link.token)

      # Assert: User authenticated
      assert verified_user.email == email

      # Assert: Magic link marked as used
      used_link = Portfolio.Repo.get!(Portfolio.Auth.MagicLink, magic_link.id)
      assert used_link.used_at != nil
    end

    test "complete flow: request → verify → create session → access admin" do
      # Arrange: Create user
      email = "admin#{System.unique_integer([:positive])}@example.com"
      user = create_user(email: email)

      # Step 1: Request magic link
      assert {:ok, magic_link} = Auth.request_magic_link(email)
      assert magic_link.used_at == nil

      # Step 2: Verify magic link
      assert {:ok, verified_user} = Auth.verify_magic_link(magic_link.token)
      assert verified_user.id == user.id

      # Step 3: Create session
      assert {:ok, session} = Auth.create_session(verified_user)
      assert session.user_id == verified_user.id
      assert session.token != nil

      # Step 4: Verify session can be retrieved
      assert retrieved_session = Auth.get_session_by_token(session.token)
      assert retrieved_session.id == session.id

      # Step 5: Verify magic link was marked as used
      used_link = Portfolio.Repo.get!(Portfolio.Auth.MagicLink, magic_link.id)
      assert used_link.used_at != nil
    end

    test "new user registration through magic link" do
      # Arrange: New email (user doesn't exist yet)
      email = "newuser#{System.unique_integer([:positive])}@example.com"

      # Assert: User doesn't exist
      assert {:error, :not_found} = Auth.get_user_by_email(email)

      # Act: Request magic link (should create user)
      assert {:ok, magic_link} = Auth.request_magic_link(email)

      # Assert: User created
      assert {:ok, user} = Auth.get_user_by_email(email)
      assert user.email == email
      assert user.role == :admin

      # Act: Verify and authenticate
      assert {:ok, verified_user} = Auth.verify_magic_link(magic_link.token)
      assert verified_user.id == user.id
    end

    test "magic link has short code for email display" do
      # Arrange: Create user
      user = create_user()

      # Act: Request magic link
      assert {:ok, magic_link} = Auth.request_magic_link(user.email)

      # Assert: Short code generated
      assert magic_link.short_code != nil
      assert String.length(magic_link.short_code) == 6
      assert magic_link.short_code =~ ~r/^[A-Z0-9]+$/
    end

    test "multiple magic links can be created for same user" do
      # Arrange: Create user
      user = create_user()

      # Act: Request multiple magic links
      assert {:ok, link1} = Auth.request_magic_link(user.email)
      assert {:ok, link2} = Auth.request_magic_link(user.email)

      # Assert: Different tokens
      assert link1.token != link2.token
      assert link1.short_code != link2.short_code

      # Assert: Both can be verified
      assert {:ok, _user} = Auth.verify_magic_link(link1.token)
      assert {:ok, _user} = Auth.verify_magic_link(link2.token)
    end

    test "session persists across multiple requests" do
      # Arrange: Create authenticated user
      user = create_user()
      {:ok, session} = Auth.create_session(user)

      # Act: Retrieve session multiple times
      session1 = Auth.get_session_by_token(session.token)
      session2 = Auth.get_session_by_token(session.token)
      session3 = Auth.get_session_by_token(session.token)

      # Assert: Same session returned
      assert session1.id == session.id
      assert session2.id == session.id
      assert session3.id == session.id
    end

    test "logout deletes session" do
      # Arrange: Create authenticated session
      user = create_user()
      {:ok, session} = Auth.create_session(user)

      # Assert: Session exists
      assert Auth.get_session_by_token(session.token) != nil

      # Act: Logout (delete session)
      assert :ok = Auth.delete_session(session)

      # Assert: Session no longer exists
      assert Auth.get_session_by_token(session.token) == nil
    end

    test "logout and re-authenticate flow" do
      # Arrange: Create user and session
      email = "user#{System.unique_integer([:positive])}@example.com"
      user = create_user(email: email)
      {:ok, session1} = Auth.create_session(user)

      # Act: Logout
      assert :ok = Auth.delete_session(session1)

      # Assert: First session deleted
      assert Auth.get_session_by_token(session1.token) == nil

      # Act: Request new magic link
      assert {:ok, magic_link} = Auth.request_magic_link(email)

      # Act: Verify and create new session
      assert {:ok, verified_user} = Auth.verify_magic_link(magic_link.token)
      assert {:ok, session2} = Auth.create_session(verified_user)

      # Assert: New session created
      assert session2.token != session1.token
      assert Auth.get_session_by_token(session2.token) != nil
    end

    test "user can have multiple active sessions" do
      # Arrange: Create user
      user = create_user()

      # Act: Create multiple sessions (different devices)
      {:ok, session1} = Auth.create_session(user)
      {:ok, session2} = Auth.create_session(user)
      {:ok, session3} = Auth.create_session(user)

      # Assert: All sessions active
      assert Auth.get_session_by_token(session1.token) != nil
      assert Auth.get_session_by_token(session2.token) != nil
      assert Auth.get_session_by_token(session3.token) != nil

      # Assert: All sessions belong to same user
      assert Auth.get_session_by_token(session1.token).user_id == user.id
      assert Auth.get_session_by_token(session2.token).user_id == user.id
      assert Auth.get_session_by_token(session3.token).user_id == user.id
    end

    test "delete all user sessions except current" do
      # Arrange: Create user with multiple sessions
      user = create_user()
      {:ok, session1} = Auth.create_session(user)
      {:ok, session2} = Auth.create_session(user)
      {:ok, session3} = Auth.create_session(user)

      # Act: Delete all sessions except session2
      assert :ok = Auth.delete_all_user_sessions_except(user, session2.id)

      # Assert: Only session2 remains
      assert Auth.get_session_by_token(session1.token) == nil
      assert Auth.get_session_by_token(session2.token) != nil
      assert Auth.get_session_by_token(session3.token) == nil
    end
  end
end
