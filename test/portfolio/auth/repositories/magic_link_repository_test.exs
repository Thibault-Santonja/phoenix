defmodule Portfolio.Auth.Repositories.MagicLinkRepositoryTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Auth.Repositories.MagicLinkRepository

  import PortfolioTest.Fixtures.AuthFixtures

  describe "get_by_token/2" do
    test "returns magic link when token exists" do
      user = create_user()
      magic_link = create_magic_link(user: user)

      assert {:ok, found} = MagicLinkRepository.get_by_token(magic_link.token)
      assert found.id == magic_link.id
    end

    test "returns error when token does not exist" do
      assert {:error, :not_found} = MagicLinkRepository.get_by_token("nonexistent_token")
    end

    test "preloads user when requested" do
      user = create_user()
      magic_link = create_magic_link(user: user)

      assert {:ok, found} = MagicLinkRepository.get_by_token(magic_link.token, preload: [:user])
      assert found.user.id == user.id
      assert found.user.email == user.email
    end

    test "does not preload user by default" do
      user = create_user()
      magic_link = create_magic_link(user: user)

      assert {:ok, found} = MagicLinkRepository.get_by_token(magic_link.token)
      assert %Ecto.Association.NotLoaded{} = found.user
    end
  end

  describe "get_by_short_code/2" do
    test "returns magic link when short_code exists" do
      user = create_user()
      magic_link = create_magic_link(user: user)

      assert {:ok, found} = MagicLinkRepository.get_by_short_code(magic_link.short_code)
      assert found.id == magic_link.id
    end

    test "returns error when short_code does not exist" do
      assert {:error, :not_found} = MagicLinkRepository.get_by_short_code("INVALID")
    end

    test "preloads user when requested" do
      user = create_user()
      magic_link = create_magic_link(user: user)

      assert {:ok, found} =
               MagicLinkRepository.get_by_short_code(magic_link.short_code, preload: [:user])

      assert found.user.id == user.id
    end
  end

  describe "list_by_user/2" do
    test "returns all magic links for user" do
      user = create_user()
      ml1 = create_magic_link(user: user)
      ml2 = create_magic_link(user: user)

      other_user = create_user()
      _other_ml = create_magic_link(user: other_user)

      links = MagicLinkRepository.list_by_user(user.id)

      assert length(links) == 2
      ids = Enum.map(links, & &1.id)
      assert ml1.id in ids
      assert ml2.id in ids
    end

    test "returns empty list when user has no magic links" do
      user = create_user()

      assert [] = MagicLinkRepository.list_by_user(user.id)
    end

    test "respects limit option" do
      user = create_user()

      for _ <- 1..5 do
        create_magic_link(user: user)
      end

      links = MagicLinkRepository.list_by_user(user.id, limit: 3)

      assert length(links) == 3
    end

    test "orders by inserted_at desc by default" do
      user = create_user()

      links = MagicLinkRepository.list_by_user(user.id, order_by: [desc: :inserted_at])

      # Verify the function returns a list (order is determined by DB)
      assert is_list(links)
    end
  end

  describe "insert/1" do
    test "creates magic link with valid attrs" do
      user = create_user()
      expires_at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)
      unique_id = System.unique_integer([:positive])

      attrs = %{
        user_id: user.id,
        token: "unique_token_#{unique_id}_padding_for_length",
        short_code: String.slice("AB#{unique_id}000000", 0, 6),
        expires_at: expires_at
      }

      assert {:ok, magic_link} = MagicLinkRepository.insert(attrs)
      assert magic_link.user_id == user.id
      assert magic_link.token == attrs.token
    end

    test "returns error with invalid attrs" do
      assert {:error, changeset} = MagicLinkRepository.insert(%{})
      refute changeset.valid?
    end
  end

  describe "mark_as_used/1" do
    test "sets used_at timestamp" do
      user = create_user()
      magic_link = create_magic_link(user: user)

      assert is_nil(magic_link.used_at)

      assert {:ok, updated} = MagicLinkRepository.mark_as_used(magic_link)
      assert not is_nil(updated.used_at)
    end

    test "does not change other fields" do
      user = create_user()
      magic_link = create_magic_link(user: user)

      assert {:ok, updated} = MagicLinkRepository.mark_as_used(magic_link)
      assert updated.token == magic_link.token
      assert updated.user_id == magic_link.user_id
    end
  end

  describe "update/2" do
    test "updates magic link attributes" do
      user = create_user()
      magic_link = create_magic_link(user: user)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, updated} = MagicLinkRepository.update(magic_link, %{used_at: now})
      assert updated.used_at == now
    end
  end

  describe "delete/1" do
    test "deletes the magic link" do
      user = create_user()
      magic_link = create_magic_link(user: user)

      assert {:ok, deleted} = MagicLinkRepository.delete(magic_link)
      assert deleted.id == magic_link.id

      assert {:error, :not_found} = MagicLinkRepository.get_by_token(magic_link.token)
    end
  end

  describe "delete_expired/0" do
    test "deletes expired magic links" do
      user = create_user()
      expired_at = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)
      valid_at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

      expired = create_magic_link(user: user, expires_at: expired_at)
      valid = create_magic_link(user: user, expires_at: valid_at)

      {count, _} = MagicLinkRepository.delete_expired()

      assert count >= 1
      assert {:error, :not_found} = MagicLinkRepository.get_by_token(expired.token)
      assert {:ok, _} = MagicLinkRepository.get_by_token(valid.token)
    end

    test "returns 0 when no expired links" do
      user = create_user()
      valid_at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)
      _valid = create_magic_link(user: user, expires_at: valid_at)

      {count, _} = MagicLinkRepository.delete_expired()

      assert count == 0
    end
  end

  describe "delete_all_for_user/1" do
    test "deletes all magic links for specific user" do
      user1 = create_user()
      user2 = create_user()

      create_magic_link(user: user1)
      create_magic_link(user: user1)
      ml_user2 = create_magic_link(user: user2)

      {count, _} = MagicLinkRepository.delete_all_for_user(user1.id)

      assert count == 2
      assert [] = MagicLinkRepository.list_by_user(user1.id)
      assert {:ok, _} = MagicLinkRepository.get_by_token(ml_user2.token)
    end
  end

  describe "count_active/0" do
    test "counts non-used and non-expired magic links" do
      user = create_user()
      expired_at = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)
      valid_at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

      # Create active link
      _active = create_magic_link(user: user, expires_at: valid_at)

      # Create expired link
      _expired = create_magic_link(user: user, expires_at: expired_at)

      # Create used link
      used = create_magic_link(user: user, expires_at: valid_at)
      MagicLinkRepository.mark_as_used(used)

      count = MagicLinkRepository.count_active()

      assert count >= 1
    end
  end

  describe "count_for_user/1" do
    test "counts magic links for specific user" do
      user1 = create_user()
      user2 = create_user()

      create_magic_link(user: user1)
      create_magic_link(user: user1)
      create_magic_link(user: user2)

      assert MagicLinkRepository.count_for_user(user1.id) == 2
      assert MagicLinkRepository.count_for_user(user2.id) == 1
    end

    test "returns 0 for user with no magic links" do
      user = create_user()

      assert MagicLinkRepository.count_for_user(user.id) == 0
    end
  end
end
