defmodule Portfolio.Photography.DomainEventsTest do
  use Portfolio.DataCase, async: false

  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.DomainEvents
  alias Portfolio.Photography
  alias Portfolio.Photography.Events.{AlbumPublished, PhotoUploaded}

  setup do
    # Subscribe to events before each test
    DomainEvents.subscribe(:album_published)
    DomainEvents.subscribe(:photo_uploaded)
    :ok
  end

  describe "publish_album/2" do
    test "publishes AlbumPublished event when album is published" do
      album = create_album(published: false)

      {:ok, published_album} = Photography.publish_album(album)

      # Assert event was published
      assert_receive {:album_published, %AlbumPublished{} = event}, 100

      # Verify event data
      assert event.album_id == published_album.id
      assert event.title == published_album.title
      assert event.slug == published_album.slug
      assert event.user_id == nil
      assert %DateTime{} = event.published_at
    end

    test "includes user_id in event when provided" do
      album = create_album(published: false)
      user_id = Ecto.UUID.generate()

      {:ok, published_album} = Photography.publish_album(album, user_id)

      assert_receive {:album_published, %AlbumPublished{} = event}, 100
      assert event.user_id == user_id
      assert event.album_id == published_album.id
    end

    test "updates album published status" do
      album = create_album(published: false)

      {:ok, published_album} = Photography.publish_album(album)

      assert published_album.published == true
    end
  end

  describe "create_photo/1" do
    test "publishes PhotoUploaded event when photo is created" do
      album = create_album()

      photo_attrs = %{
        album_id: album.id,
        original_filename: "test.jpg",
        file_path: "/uploads/test.jpg",
        hash: "abc123",
        display_order: 0
      }

      {:ok, photo} = Photography.create_photo(photo_attrs)

      # Assert event was published
      assert_receive {:photo_uploaded, %PhotoUploaded{} = event}, 100

      # Verify event data
      assert event.photo_id == photo.id
      assert event.album_id == photo.album_id
      assert event.file_path == photo.file_path
      assert event.hash == photo.hash
      assert %DateTime{} = event.uploaded_at
    end

    test "does not publish event if photo creation fails" do
      album = create_album()

      # Invalid attrs - missing required album_id will cause failure
      {:error, _changeset} =
        Photography.create_photo(%{
          original_filename: "test.jpg",
          file_path: "/test.jpg"
          # Missing album_id and other required fields
        })

      # Flush any events from album creation
      receive do
        {:album_published, _} -> :ok
      after
        0 -> :ok
      end

      # Should not receive photo uploaded event
      refute_receive {:photo_uploaded, _}, 100
    end
  end
end
