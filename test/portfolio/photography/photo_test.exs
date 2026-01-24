defmodule Portfolio.Photography.PhotoTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Photography.{Album, Photo}

  describe "changeset/2" do
    setup do
      # Create an album for our photo tests
      album =
        %Album{}
        |> Album.changeset(%{
          title: "Test Album",
          type: :wedding,
          date_prise_vue: ~D[2024-01-15]
        })
        |> Repo.insert!()

      %{album_id: album.id}
    end

    @valid_attrs %{
      original_filename: "IMG_1234.jpg",
      file_path: "/uploads/photos/2024/img_1234.jpg",
      title: "Coucher de soleil magnifique",
      description: "Une belle photo de coucher de soleil sur la plage",
      display_order: 1,
      taken_at: ~D[2024-06-15],
      published: true,
      hash: "abc123def456",
      mime_type: "image/jpeg",
      exif_data: %{"camera" => "Canon EOS R5", "iso" => "100"}
    }

    test "valid changeset with all fields", %{album_id: album_id} do
      attrs = Map.put(@valid_attrs, :album_id, album_id)
      changeset = Photo.changeset(%Photo{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :album_id) == album_id
      assert get_change(changeset, :original_filename) == "IMG_1234.jpg"
      assert get_change(changeset, :file_path) == "/uploads/photos/2024/img_1234.jpg"
      assert get_change(changeset, :title) == "Coucher de soleil magnifique"
      assert get_change(changeset, :display_order) == 1
    end

    test "valid changeset with only required fields", %{album_id: album_id} do
      attrs = %{
        album_id: album_id,
        original_filename: "test.jpg",
        file_path: "/test.jpg"
      }

      changeset = Photo.changeset(%Photo{}, attrs)

      assert changeset.valid?
    end

    test "generates slug from title", %{album_id: album_id} do
      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.put(:title, "Coucher de soleil")

      changeset = Photo.changeset(%Photo{}, attrs)

      assert get_change(changeset, :slug) == "coucher-de-soleil"
    end

    test "generates slug with special characters removed", %{album_id: album_id} do
      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.put(:title, "L'été 2024 à Taïwan!")

      changeset = Photo.changeset(%Photo{}, attrs)

      assert get_change(changeset, :slug) == "lete-2024-a-taiwan"
    end

    test "generates slug with spaces replaced by dashes", %{album_id: album_id} do
      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.put(:title, "Un beau jour ensoleillé")

      changeset = Photo.changeset(%Photo{}, attrs)

      assert get_change(changeset, :slug) == "un-beau-jour-ensoleille"
    end

    test "does not generate slug when title is not provided", %{album_id: album_id} do
      attrs = %{
        album_id: album_id,
        original_filename: "test.jpg",
        file_path: "/test.jpg"
      }

      changeset = Photo.changeset(%Photo{}, attrs)

      refute get_change(changeset, :slug)
    end

    test "invalid without album_id" do
      attrs = Map.delete(@valid_attrs, :album_id)
      changeset = Photo.changeset(%Photo{}, attrs)

      refute changeset.valid?
      assert %{album_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without original_filename", %{album_id: album_id} do
      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.delete(:original_filename)

      changeset = Photo.changeset(%Photo{}, attrs)

      refute changeset.valid?
      assert %{original_filename: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without file_path", %{album_id: album_id} do
      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.delete(:file_path)

      changeset = Photo.changeset(%Photo{}, attrs)

      refute changeset.valid?
      assert %{file_path: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid with title too long", %{album_id: album_id} do
      long_title = String.duplicate("a", 201)

      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.put(:title, long_title)

      changeset = Photo.changeset(%Photo{}, attrs)

      refute changeset.valid?
      assert %{title: ["should be at most 200 character(s)"]} = errors_on(changeset)
    end

    test "valid with title at max length (200)", %{album_id: album_id} do
      max_title = String.duplicate("a", 200)

      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.put(:title, max_title)

      changeset = Photo.changeset(%Photo{}, attrs)

      assert changeset.valid?
    end

    test "invalid with description too long", %{album_id: album_id} do
      long_desc = String.duplicate("a", 2001)

      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.put(:description, long_desc)

      changeset = Photo.changeset(%Photo{}, attrs)

      refute changeset.valid?
      assert %{description: ["should be at most 2000 character(s)"]} = errors_on(changeset)
    end

    test "valid with description at max length (2000)", %{album_id: album_id} do
      max_desc = String.duplicate("a", 2000)

      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.put(:description, max_desc)

      changeset = Photo.changeset(%Photo{}, attrs)

      assert changeset.valid?
    end

    test "invalid with negative display_order", %{album_id: album_id} do
      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.put(:display_order, -1)

      changeset = Photo.changeset(%Photo{}, attrs)

      refute changeset.valid?
      assert %{display_order: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "valid with display_order of 0", %{album_id: album_id} do
      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.put(:display_order, 0)

      changeset = Photo.changeset(%Photo{}, attrs)

      assert changeset.valid?
    end

    test "invalid with future taken_at date", %{album_id: album_id} do
      future_date = Date.add(Date.utc_today(), 30)

      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.put(:taken_at, future_date)

      changeset = Photo.changeset(%Photo{}, attrs)

      refute changeset.valid?
      assert %{taken_at: ["ne peut pas être dans le futur"]} = errors_on(changeset)
    end

    test "valid with taken_at as today", %{album_id: album_id} do
      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.put(:taken_at, Date.utc_today())

      changeset = Photo.changeset(%Photo{}, attrs)

      assert changeset.valid?
    end

    test "valid with taken_at in the past", %{album_id: album_id} do
      past_date = ~D[2020-01-01]

      attrs =
        @valid_attrs
        |> Map.put(:album_id, album_id)
        |> Map.put(:taken_at, past_date)

      changeset = Photo.changeset(%Photo{}, attrs)

      assert changeset.valid?
    end

    test "published defaults to true", %{album_id: album_id} do
      attrs = %{
        album_id: album_id,
        original_filename: "test.jpg",
        file_path: "/test.jpg"
      }

      changeset = Photo.changeset(%Photo{}, attrs)
      photo = Repo.insert!(changeset)

      assert photo.published == true
    end

    test "display_order defaults to 0", %{album_id: album_id} do
      attrs = %{
        album_id: album_id,
        original_filename: "test.jpg",
        file_path: "/test.jpg"
      }

      changeset = Photo.changeset(%Photo{}, attrs)
      photo = Repo.insert!(changeset)

      assert photo.display_order == 0
    end

    test "exif_data defaults to empty map", %{album_id: album_id} do
      attrs = %{
        album_id: album_id,
        original_filename: "test.jpg",
        file_path: "/test.jpg"
      }

      changeset = Photo.changeset(%Photo{}, attrs)
      photo = Repo.insert!(changeset)

      assert photo.exif_data == %{}
    end

    test "variants defaults to empty map", %{album_id: album_id} do
      attrs = %{
        album_id: album_id,
        original_filename: "test.jpg",
        file_path: "/test.jpg"
      }

      changeset = Photo.changeset(%Photo{}, attrs)
      photo = Repo.insert!(changeset)

      assert photo.variants == %{}
    end

    test "processing_status defaults to pending", %{album_id: album_id} do
      attrs = %{
        album_id: album_id,
        original_filename: "test.jpg",
        file_path: "/test.jpg"
      }

      changeset = Photo.changeset(%Photo{}, attrs)
      photo = Repo.insert!(changeset)

      assert photo.processing_status == "pending"
    end

    test "valid with processing_status as completed", %{album_id: album_id} do
      attrs = %{
        album_id: album_id,
        original_filename: "test.jpg",
        file_path: "/test.jpg",
        processing_status: "completed"
      }

      changeset = Photo.changeset(%Photo{}, attrs)

      assert changeset.valid?
    end

    test "valid with variants map", %{album_id: album_id} do
      variants = %{
        "thumbnail" => "/uploads/photos/abc12345/thumbnail.webp",
        "small" => "/uploads/photos/abc12345/small.webp",
        "medium" => "/uploads/photos/abc12345/medium.webp",
        "large" => "/uploads/photos/abc12345/large.webp"
      }

      attrs = %{
        album_id: album_id,
        original_filename: "test.jpg",
        file_path: "/test.jpg",
        variants: variants
      }

      changeset = Photo.changeset(%Photo{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :variants) == variants
    end

    test "invalid with invalid processing_status", %{album_id: album_id} do
      attrs = %{
        album_id: album_id,
        original_filename: "test.jpg",
        file_path: "/test.jpg",
        processing_status: "invalid_status"
      }

      changeset = Photo.changeset(%Photo{}, attrs)

      refute changeset.valid?
      assert %{processing_status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "processing?/1" do
    test "returns true when status is pending" do
      photo = %Photo{processing_status: "pending"}
      assert Photo.processing?(photo)
    end

    test "returns true when status is processing" do
      photo = %Photo{processing_status: "processing"}
      assert Photo.processing?(photo)
    end

    test "returns false when status is completed" do
      photo = %Photo{processing_status: "completed"}
      refute Photo.processing?(photo)
    end

    test "returns false when status is failed" do
      photo = %Photo{processing_status: "failed"}
      refute Photo.processing?(photo)
    end
  end

  describe "failed?/1" do
    test "returns true when status is failed" do
      photo = %Photo{processing_status: "failed"}
      assert Photo.failed?(photo)
    end

    test "returns false when status is pending" do
      photo = %Photo{processing_status: "pending"}
      refute Photo.failed?(photo)
    end

    test "returns false when status is processing" do
      photo = %Photo{processing_status: "processing"}
      refute Photo.failed?(photo)
    end

    test "returns false when status is completed" do
      photo = %Photo{processing_status: "completed"}
      refute Photo.failed?(photo)
    end
  end

  describe "unique constraints" do
    setup do
      album =
        %Album{}
        |> Album.changeset(%{
          title: "Test Album",
          type: :wedding,
          date_prise_vue: ~D[2024-01-15]
        })
        |> Repo.insert!()

      %{album_id: album.id}
    end

    test "hash must be unique", %{album_id: album_id} do
      hash = "unique_hash_123"

      # Insert first photo with hash
      %Photo{}
      |> Photo.changeset(%{
        album_id: album_id,
        original_filename: "photo1.jpg",
        file_path: "/photo1.jpg",
        hash: hash
      })
      |> Repo.insert!()

      # Try to insert second photo with same hash
      changeset =
        %Photo{}
        |> Photo.changeset(%{
          album_id: album_id,
          original_filename: "photo2.jpg",
          file_path: "/photo2.jpg",
          hash: hash
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{hash: ["has already been taken"]} = errors_on(changeset)
    end

    test "slug must be unique within album", %{album_id: album_id} do
      # Insert first photo with slug
      %Photo{}
      |> Photo.changeset(%{
        album_id: album_id,
        original_filename: "sunset1.jpg",
        file_path: "/sunset1.jpg",
        title: "Sunset"
      })
      |> Repo.insert!()

      # Try to insert second photo with same slug in same album
      changeset =
        %Photo{}
        |> Photo.changeset(%{
          album_id: album_id,
          original_filename: "sunset2.jpg",
          file_path: "/sunset2.jpg",
          title: "Sunset"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{album_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "slug can be same across different albums" do
      # Create two albums
      album1 =
        %Album{}
        |> Album.changeset(%{
          title: "Album 1",
          type: :wedding,
          date_prise_vue: ~D[2024-01-15]
        })
        |> Repo.insert!()

      album2 =
        %Album{}
        |> Album.changeset(%{
          title: "Album 2",
          type: :events,
          date_prise_vue: ~D[2024-02-15]
        })
        |> Repo.insert!()

      # Insert photo with same title in first album
      %Photo{}
      |> Photo.changeset(%{
        album_id: album1.id,
        original_filename: "sunset1.jpg",
        file_path: "/sunset1.jpg",
        title: "Sunset"
      })
      |> Repo.insert!()

      # Insert photo with same title in second album (should succeed)
      changeset =
        %Photo{}
        |> Photo.changeset(%{
          album_id: album2.id,
          original_filename: "sunset2.jpg",
          file_path: "/sunset2.jpg",
          title: "Sunset"
        })

      assert {:ok, _photo} = Repo.insert(changeset)
    end

    test "different titles generate different slugs", %{album_id: album_id} do
      changeset1 =
        %Photo{}
        |> Photo.changeset(%{
          album_id: album_id,
          original_filename: "photo1.jpg",
          file_path: "/photo1.jpg",
          title: "Sunset Beach"
        })

      changeset2 =
        %Photo{}
        |> Photo.changeset(%{
          album_id: album_id,
          original_filename: "photo2.jpg",
          file_path: "/photo2.jpg",
          title: "Mountain Sunrise"
        })

      slug1 = get_change(changeset1, :slug)
      slug2 = get_change(changeset2, :slug)

      assert slug1 == "sunset-beach"
      assert slug2 == "mountain-sunrise"
      assert slug1 != slug2
    end
  end

  describe "foreign key constraints" do
    test "cannot create photo with non-existent album_id" do
      fake_album_id = Ecto.UUID.generate()

      changeset =
        %Photo{}
        |> Photo.changeset(%{
          album_id: fake_album_id,
          original_filename: "test.jpg",
          file_path: "/test.jpg"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{album_id: ["does not exist"]} = errors_on(changeset)
    end

    test "photos are deleted when album is deleted (CASCADE)" do
      # Create album
      album =
        %Album{}
        |> Album.changeset(%{
          title: "Test Album",
          type: :wedding,
          date_prise_vue: ~D[2024-01-15]
        })
        |> Repo.insert!()

      # Create photo
      photo =
        %Photo{}
        |> Photo.changeset(%{
          album_id: album.id,
          original_filename: "test.jpg",
          file_path: "/test.jpg"
        })
        |> Repo.insert!()

      # Delete album
      Repo.delete!(album)

      # Photo should be deleted too
      assert is_nil(Repo.get(Photo, photo.id))
    end
  end
end
