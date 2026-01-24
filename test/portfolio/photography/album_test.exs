defmodule Portfolio.Photography.AlbumTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Photography.Album

  describe "changeset/2" do
    @valid_attrs %{
      title: "Mariage de Claire & Damien",
      type: :wedding,
      date_prise_vue: ~D[2024-06-15],
      description: "Un beau mariage ensoleillé",
      location: "Château de Coucy"
    }

    test "valid changeset with required fields" do
      changeset = Album.changeset(%Album{}, @valid_attrs)

      assert changeset.valid?
      assert get_change(changeset, :title) == "Mariage de Claire & Damien"
      assert get_change(changeset, :type) == :wedding
      assert get_change(changeset, :date_prise_vue) == ~D[2024-06-15]
    end

    test "generates slug from title" do
      changeset = Album.changeset(%Album{}, @valid_attrs)

      assert get_change(changeset, :slug) == "mariage-de-claire-damien"
    end

    test "generates slug with special characters removed" do
      attrs = %{@valid_attrs | title: "L'été 2024 à Taïwan!"}
      changeset = Album.changeset(%Album{}, attrs)

      assert get_change(changeset, :slug) == "lete-2024-a-taiwan"
    end

    test "generates slug with spaces replaced by dashes" do
      attrs = %{@valid_attrs | title: "Concert de musique classique"}
      changeset = Album.changeset(%Album{}, attrs)

      assert get_change(changeset, :slug) == "concert-de-musique-classique"
    end

    test "invalid without title" do
      attrs = Map.delete(@valid_attrs, :title)
      changeset = Album.changeset(%Album{}, attrs)

      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without type" do
      attrs = Map.delete(@valid_attrs, :type)
      changeset = Album.changeset(%Album{}, attrs)

      refute changeset.valid?
      assert %{type: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without date_prise_vue" do
      attrs = Map.delete(@valid_attrs, :date_prise_vue)
      changeset = Album.changeset(%Album{}, attrs)

      refute changeset.valid?
      assert %{date_prise_vue: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid with title too short" do
      attrs = %{@valid_attrs | title: "AB"}
      changeset = Album.changeset(%Album{}, attrs)

      refute changeset.valid?
      assert %{title: ["should be at least 3 character(s)"]} = errors_on(changeset)
    end

    test "invalid with title too long" do
      attrs = %{@valid_attrs | title: String.duplicate("a", 201)}
      changeset = Album.changeset(%Album{}, attrs)

      refute changeset.valid?
      assert %{title: ["should be at most 200 character(s)"]} = errors_on(changeset)
    end

    test "valid with title at minimum length (3 chars)" do
      attrs = %{@valid_attrs | title: "ABC"}
      changeset = Album.changeset(%Album{}, attrs)

      assert changeset.valid?
    end

    test "valid with title at maximum length (200 chars)" do
      attrs = %{@valid_attrs | title: String.duplicate("a", 200)}
      changeset = Album.changeset(%Album{}, attrs)

      assert changeset.valid?
    end

    test "invalid with description too long" do
      attrs = %{@valid_attrs | description: String.duplicate("a", 5001)}
      changeset = Album.changeset(%Album{}, attrs)

      refute changeset.valid?
      assert %{description: ["should be at most 5000 character(s)"]} = errors_on(changeset)
    end

    test "valid with description at maximum length (5000 chars)" do
      attrs = %{@valid_attrs | description: String.duplicate("a", 5000)}
      changeset = Album.changeset(%Album{}, attrs)

      assert changeset.valid?
    end

    test "invalid with unknown type" do
      attrs = %{@valid_attrs | type: :unknown_type}
      changeset = Album.changeset(%Album{}, attrs)

      refute changeset.valid?
      assert %{type: ["is invalid"]} = errors_on(changeset)
    end

    test "valid with all known types" do
      known_types = [
        :couples,
        :wedding,
        :motherhood,
        :events,
        :landscape,
        :street,
        :music,
        :reenactment,
        :amvcc,
        :china,
        :japan,
        :taiwan
      ]

      for type <- known_types do
        attrs = %{@valid_attrs | type: type}
        changeset = Album.changeset(%Album{}, attrs)

        assert changeset.valid?, "Type #{type} should be valid"
      end
    end

    test "invalid with future date" do
      future_date = Date.add(Date.utc_today(), 1)
      attrs = %{@valid_attrs | date_prise_vue: future_date}
      changeset = Album.changeset(%Album{}, attrs)

      refute changeset.valid?
      assert %{date_prise_vue: ["ne peut pas être dans le futur"]} = errors_on(changeset)
    end

    test "valid with today's date" do
      attrs = %{@valid_attrs | date_prise_vue: Date.utc_today()}
      changeset = Album.changeset(%Album{}, attrs)

      assert changeset.valid?
    end

    test "valid with past date" do
      past_date = Date.add(Date.utc_today(), -100)
      attrs = %{@valid_attrs | date_prise_vue: past_date}
      changeset = Album.changeset(%Album{}, attrs)

      assert changeset.valid?
    end

    test "published defaults to false" do
      changeset = Album.changeset(%Album{}, @valid_attrs)
      {:ok, album} = Repo.insert(changeset)

      assert album.published == false
    end

    test "can set published to true" do
      attrs = Map.put(@valid_attrs, :published, true)
      changeset = Album.changeset(%Album{}, attrs)
      {:ok, album} = Repo.insert(changeset)

      assert album.published == true
    end

    test "exif_data defaults to empty map" do
      changeset = Album.changeset(%Album{}, @valid_attrs)
      {:ok, album} = Repo.insert(changeset)

      assert album.exif_data == %{}
    end

    test "can store custom exif_data" do
      attrs = Map.put(@valid_attrs, :exif_data, %{"camera" => "Canon EOS R5", "iso" => 400})
      changeset = Album.changeset(%Album{}, attrs)
      {:ok, album} = Repo.insert(changeset)

      assert album.exif_data == %{"camera" => "Canon EOS R5", "iso" => 400}
    end
  end

  describe "unique constraints" do
    test "slug must be unique" do
      # Insert first album
      changeset1 =
        Album.changeset(%Album{}, %{
          title: "Mon Album",
          type: :wedding,
          date_prise_vue: ~D[2024-01-01]
        })

      {:ok, _album1} = Repo.insert(changeset1)

      # Try to insert second album with same title (same slug)
      changeset2 =
        Album.changeset(%Album{}, %{
          title: "Mon Album",
          type: :couples,
          date_prise_vue: ~D[2024-02-01]
        })

      assert {:error, changeset} = Repo.insert(changeset2)
      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "different titles generate different slugs" do
      changeset1 =
        Album.changeset(%Album{}, %{
          title: "Album 1",
          type: :wedding,
          date_prise_vue: ~D[2024-01-01]
        })

      {:ok, album1} = Repo.insert(changeset1)

      changeset2 =
        Album.changeset(%Album{}, %{
          title: "Album 2",
          type: :couples,
          date_prise_vue: ~D[2024-02-01]
        })

      {:ok, album2} = Repo.insert(changeset2)

      assert album1.slug != album2.slug
    end
  end
end
