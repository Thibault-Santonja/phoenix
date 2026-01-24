defmodule Portfolio.Photography.Services.PhotoDeletionServiceTest do
  use Portfolio.DataCase, async: true

  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.Photo
  alias Portfolio.Photography.Services.PhotoDeletionService
  alias Portfolio.Repo

  describe "execute/2" do
    test "deletes photo from database" do
      album = create_album()
      # Create photo with a file_path that doesn't exist - storage will return :ok anyway
      photo = create_photo(album: album, file_path: "/uploads/photos/nonexistent/original.jpg")

      assert {:ok, %{photo: deleted_photo}} = PhotoDeletionService.execute(photo)
      assert deleted_photo.id == photo.id

      # Photo should no longer exist in DB
      assert Repo.get(Photo, photo.id) == nil
    end

    test "emits photo_deleted domain event on success" do
      album = create_album()
      photo = create_photo(album: album, file_path: "/uploads/photos/nonexistent/original.jpg")

      DomainEvents.subscribe(:photo_deleted)

      assert {:ok, _} = PhotoDeletionService.execute(photo)

      assert_receive {:photo_deleted, event}
      assert event.photo_id == photo.id
      assert event.album_id == photo.album_id
    end

    test "returns file ok when storage file does not exist" do
      album = create_album()
      # File doesn't exist, but LocalStorage returns :ok for non-existent files
      photo = create_photo(album: album, file_path: "/uploads/photos/nonexistent/original.jpg")

      assert {:ok, %{photo: _deleted, file: :ok}} = PhotoDeletionService.execute(photo)
    end

    test "event contains correct metadata" do
      album = create_album()

      photo =
        create_photo(
          album: album,
          file_path: "/uploads/photos/testphoto/original.jpg"
        )

      DomainEvents.subscribe(:photo_deleted)

      assert {:ok, _} = PhotoDeletionService.execute(photo)

      assert_receive {:photo_deleted, event}
      assert event.file_path == "/uploads/photos/testphoto/original.jpg"
      assert %DateTime{} = event.deleted_at
    end

    test "accepts empty options" do
      album = create_album()
      photo = create_photo(album: album, file_path: "/uploads/photos/nonexistent/original.jpg")

      assert {:ok, _} = PhotoDeletionService.execute(photo, [])
    end
  end
end
