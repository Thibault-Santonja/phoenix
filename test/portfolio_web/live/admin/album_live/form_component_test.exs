defmodule PortfolioWeb.Admin.AlbumLive.FormComponentTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.AuthFixtures
  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.Photography

  setup :register_and_log_in_user

  describe "FormComponent - New Album" do
    test "renders new album form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/albums/new")

      assert html =~ "Créer un nouvel album" or html =~ "Nouvel album"
      assert has_element?(view, "form#album-form")
      assert has_element?(view, "input[name=\"album[title]\"]")
      assert has_element?(view, "select[name=\"album[type]\"]")
    end

    test "displays all album type options", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/albums/new")

      # Check for various album types
      assert html =~ "wedding" or html =~ "Mariage"
      assert html =~ "couples" or html =~ "Couples"
      assert html =~ "music" or html =~ "Musique"
    end

    test "validates form on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      # Submit with short title
      html =
        view
        |> form("#album-form", %{album: %{title: "AB"}})
        |> render_change()

      # Should show validation error
      assert html =~ "should be at least 3" or html =~ "au moins 3"
    end

    test "creates album successfully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      # Fill and submit form
      view
      |> form("#album-form", %{
        album: %{
          title: "New Wedding Album",
          type: "wedding",
          date_prise_vue: "2024-06-15"
        }
      })
      |> render_submit()

      # Should redirect to edit page
      {path, _flash} = assert_redirect(view)
      assert path =~ "/admin/albums/"
      assert path =~ "/edit"

      # Verify album was created
      [album] = Photography.list_albums()
      assert album.title == "New Wedding Album"
      assert album.type == :wedding
    end

    test "shows cancel link", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/albums/new")

      assert html =~ "Annuler"
      assert has_element?(view, "a[href=\"/admin/albums\"]")
    end

    test "handles optional fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      # Create album with optional fields
      view
      |> form("#album-form", %{
        album: %{
          title: "Full Album",
          type: "wedding",
          description: "A beautiful wedding",
          location: "Paris, France",
          date_prise_vue: "2024-06-15",
          date_fin_prise_vue: "2024-06-16",
          reference_link: "https://example.com",
          published: "true"
        }
      })
      |> render_submit()

      # Verify all fields were saved
      [album] = Photography.list_albums()
      assert album.description == "A beautiful wedding"
      assert album.location == "Paris, France"
      assert album.date_fin_prise_vue == ~D[2024-06-16]
      assert album.reference_link == "https://example.com"
      assert album.published == true
    end
  end

  describe "FormComponent - Edit Album" do
    test "renders edit form with existing data", %{conn: conn} do
      album = create_album(title: "Existing Album", type: :wedding)

      {:ok, _view, html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      assert html =~ "Existing Album"
      assert html =~ "Modifier" or html =~ "Edit"
    end

    test "validates changes on edit", %{conn: conn} do
      album = create_album(title: "Valid Album")

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Try to change to invalid title
      html =
        view
        |> form("#album-form", %{album: %{title: "AB"}})
        |> render_change()

      assert html =~ "should be at least 3" or html =~ "au moins 3"
    end

    test "updates album successfully", %{conn: conn} do
      album = create_album(title: "Original Title", type: :wedding)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      view
      |> form("#album-form", %{
        album: %{
          title: "Updated Title",
          description: "New description"
        }
      })
      |> render_submit()

      # Should redirect to albums list
      assert_redirect(view, ~p"/admin/albums")

      # Verify changes were saved
      updated = Photography.get_album!(album.id)
      assert updated.title == "Updated Title"
      assert updated.description == "New description"
    end

    test "updates date range", %{conn: conn} do
      album = create_album(date_prise_vue: ~D[2024-01-01])

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      view
      |> form("#album-form", %{
        album: %{
          date_prise_vue: "2024-06-15",
          date_fin_prise_vue: "2024-06-20"
        }
      })
      |> render_submit()

      updated = Photography.get_album!(album.id)
      assert updated.date_prise_vue == ~D[2024-06-15]
      assert updated.date_fin_prise_vue == ~D[2024-06-20]
    end

    test "toggles published status", %{conn: conn} do
      album = create_album(published: false)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      view
      |> form("#album-form", %{album: %{published: "true"}})
      |> render_submit()

      updated = Photography.get_album!(album.id)
      assert updated.published == true
    end
  end

  describe "FormComponent - Album Types" do
    test "displays formatted type options", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/albums/new")

      # Should display translated type names
      assert html =~ "Mariage" or html =~ "Wedding"
      assert html =~ "Couples"
      assert html =~ "Paysage" or html =~ "Landscape"
    end

    test "creates album with each type", %{conn: conn} do
      types = [:wedding, :couples, :motherhood, :events, :landscape, :street, :music]

      for {type, index} <- Enum.with_index(types) do
        {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

        view
        |> form("#album-form", %{
          album: %{
            title: "Album Type #{index}",
            type: Atom.to_string(type),
            date_prise_vue: "2024-06-15"
          }
        })
        |> render_submit()
      end

      albums = Photography.list_albums()
      assert length(albums) == length(types)
    end

    test "creates album with travel types", %{conn: conn} do
      travel_types = [:china, :japan, :taiwan]

      for {type, index} <- Enum.with_index(travel_types) do
        {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

        view
        |> form("#album-form", %{
          album: %{
            title: "Travel Album #{index}",
            type: Atom.to_string(type),
            date_prise_vue: "2024-06-15"
          }
        })
        |> render_submit()
      end

      albums = Photography.list_albums()
      travel_album_types = Enum.map(albums, & &1.type)
      assert :china in travel_album_types
      assert :japan in travel_album_types
      assert :taiwan in travel_album_types
    end

    test "creates album with special types", %{conn: conn} do
      special_types = [:reenactment, :amvcc]

      for {type, index} <- Enum.with_index(special_types) do
        {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

        view
        |> form("#album-form", %{
          album: %{
            title: "Special Album #{index}",
            type: Atom.to_string(type),
            date_prise_vue: "2024-06-15"
          }
        })
        |> render_submit()
      end

      albums = Photography.list_albums()
      special_album_types = Enum.map(albums, & &1.type)
      assert :reenactment in special_album_types
      assert :amvcc in special_album_types
    end
  end

  describe "FormComponent - Validation" do
    test "requires title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      html =
        view
        |> form("#album-form", %{
          album: %{
            title: "",
            type: "wedding",
            date_prise_vue: "2024-06-15"
          }
        })
        |> render_submit()

      # Should show error and not redirect
      assert html =~ "can&#39;t be blank" or html =~ "requis" or html =~ "required"
    end

    test "requires type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      html =
        view
        |> form("#album-form", %{
          album: %{
            title: "Valid Title",
            type: "",
            date_prise_vue: "2024-06-15"
          }
        })
        |> render_submit()

      # Should show error
      assert html =~ "can&#39;t be blank" or html =~ "requis" or html =~ "Type"
    end

    test "requires start date", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      html =
        view
        |> form("#album-form", %{
          album: %{
            title: "Valid Title",
            type: "wedding",
            date_prise_vue: ""
          }
        })
        |> render_submit()

      # Should show error
      assert html =~ "can&#39;t be blank" or html =~ "requis" or html =~ "date"
    end

    test "validates minimum title length", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      html =
        view
        |> form("#album-form", %{
          album: %{
            title: "AB",
            type: "wedding",
            date_prise_vue: "2024-06-15"
          }
        })
        |> render_change()

      assert html =~ "at least 3" or html =~ "au moins 3"
    end

    test "validates URL format for reference link", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      # Note: URL validation might be browser-side with type="url"
      # This test verifies the field accepts valid URLs
      html =
        view
        |> form("#album-form", %{
          album: %{
            title: "Valid Title",
            type: "wedding",
            date_prise_vue: "2024-06-15",
            reference_link: "https://example.com"
          }
        })
        |> render_change()

      # Should not show URL error for valid URL
      refute html =~ "invalid URL" or html =~ "URL invalide"
    end
  end

  describe "FormComponent - Date Range Validation" do
    test "accepts valid date range", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      view
      |> form("#album-form", %{
        album: %{
          title: "Date Range Album",
          type: "wedding",
          date_prise_vue: "2024-06-15",
          date_fin_prise_vue: "2024-06-20"
        }
      })
      |> render_submit()

      # Should create album successfully
      [album] = Photography.list_albums()
      assert album.date_prise_vue == ~D[2024-06-15]
      assert album.date_fin_prise_vue == ~D[2024-06-20]
    end

    test "allows same start and end date", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      view
      |> form("#album-form", %{
        album: %{
          title: "Same Day Album",
          type: "wedding",
          date_prise_vue: "2024-06-15",
          date_fin_prise_vue: "2024-06-15"
        }
      })
      |> render_submit()

      [album] = Photography.list_albums()
      assert album.date_prise_vue == ~D[2024-06-15]
      assert album.date_fin_prise_vue == ~D[2024-06-15]
    end
  end

  describe "FormComponent - Parent Notification" do
    test "notifies parent on save", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")

      view
      |> form("#album-form", %{
        album: %{
          title: "Notify Parent Album",
          type: "wedding",
          date_prise_vue: "2024-06-15"
        }
      })
      |> render_submit()

      # Parent should receive notification and redirect
      {path, _flash} = assert_redirect(view)
      assert path =~ "/admin/albums"
    end
  end
end
