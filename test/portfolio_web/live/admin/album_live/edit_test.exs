defmodule PortfolioWeb.Admin.AlbumLive.EditTest do
  use PortfolioWeb.ConnCase

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.AuthFixtures
  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.Photography

  describe "mount" do
    setup :register_and_log_in_user

    test "displays album edit form", %{conn: conn} do
      album = create_album(title: "Test Album", type: :wedding)

      {:ok, view, html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      assert html =~ "Modifier l&#39;album"
      assert html =~ "Test Album"
      assert has_element?(view, "form")
      assert has_element?(view, "input[name=\"album[title]\"]")
      assert has_element?(view, "select[name=\"album[type]\"]")
    end

    test "displays photos count", %{conn: conn} do
      album = create_album_with_photos(3)

      {:ok, _view, html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      assert html =~ "Photos de l&#39;album (3)"
    end

    test "displays upload zone", %{conn: conn} do
      album = create_album()

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      assert has_element?(view, "form[phx-submit=\"upload\"]")
      assert has_element?(view, "input[type=\"file\"]")
    end
  end

  describe "save event" do
    setup :register_and_log_in_user

    test "updates album successfully", %{conn: conn} do
      album = create_album(title: "Original Title")

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      view
      |> form("#album-form", %{
        album: %{
          title: "Updated Title",
          description: "Updated description"
        }
      })
      |> render_submit()

      # FormComponent redirects to albums list after edit
      assert_redirected(view, ~p"/admin/albums")

      updated_album = Photography.get_album!(album.id)
      assert updated_album.title == "Updated Title"
      assert updated_album.description == "Updated description"
    end

    test "updates date range", %{conn: conn} do
      album = create_album(date_prise_vue: ~D[2024-01-15])

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      view
      |> form("#album-form", %{
        album: %{
          date_prise_vue: "2024-01-15",
          date_fin_prise_vue: "2024-01-20"
        }
      })
      |> render_submit()

      updated_album = Photography.get_album!(album.id)
      assert updated_album.date_prise_vue == ~D[2024-01-15]
      assert updated_album.date_fin_prise_vue == ~D[2024-01-20]
    end

    test "shows validation errors", %{conn: conn} do
      album = create_album()

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      html =
        view
        |> form("#album-form", %{album: %{title: "AB"}})
        |> render_submit()

      # Le titre doit faire au moins 3 caractères
      assert html =~ "should be at least 3 character" or html =~ "au moins 3"
    end

    test "validates date range - end date must be after start date", %{conn: conn} do
      album = create_album(date_prise_vue: ~D[2024-01-20])

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      html =
        view
        |> form("#album-form", %{
          album: %{
            date_prise_vue: "2024-01-20",
            date_fin_prise_vue: "2024-01-15"
          }
        })
        |> render_submit()

      assert html =~ "doit être après ou égale"
    end
  end

  describe "delete_photo event" do
    setup :register_and_log_in_user

    test "deletes a photo", %{conn: conn} do
      album = create_album_with_photos(3)
      photo = List.first(album.photos)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      html =
        view
        |> element(~s|button[phx-click="delete_photo"][phx-value-id="#{photo.id}"]|)
        |> render_click()

      assert html =~ "Photo supprimée"

      # Vérifier que l'album n'a plus que 2 photos
      updated_album = Photography.get_album!(album.id, preload: [:photos])
      assert length(updated_album.photos) == 2
      refute Enum.any?(updated_album.photos, &(&1.id == photo.id))
    end
  end

  describe "edit_photo event" do
    setup :register_and_log_in_user

    test "opens photo edit modal", %{conn: conn} do
      album = create_album_with_photos(1)
      photo = List.first(album.photos)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      html =
        view
        |> element(~s|img[phx-click="edit_photo"][phx-value-id="#{photo.id}"]|)
        |> render_click()

      assert html =~ "Modifier la photo"
      assert has_element?(view, "input[name=\"photo[title]\"]")
      assert has_element?(view, "textarea[name=\"photo[description]\"]")
    end

    test "closes modal on cancel", %{conn: conn} do
      album = create_album_with_photos(1)
      photo = List.first(album.photos)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Ouvrir la modal
      view
      |> element(~s|img[phx-click="edit_photo"][phx-value-id="#{photo.id}"]|)
      |> render_click()

      # Fermer la modal
      html =
        view
        |> element(~s|button[phx-click="close_photo_modal"]|)
        |> render_click()

      refute html =~ "Modifier la photo"
    end
  end

  describe "save_photo event" do
    setup :register_and_log_in_user

    test "updates photo successfully", %{conn: conn} do
      album = create_album_with_photos(1)
      photo = List.first(album.photos)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Ouvrir la modal
      view
      |> element(~s|img[phx-click="edit_photo"][phx-value-id="#{photo.id}"]|)
      |> render_click()

      # Soumettre le formulaire
      html =
        view
        |> form(~s|form[phx-submit="save_photo"]|, %{
          photo: %{
            title: "Updated Photo Title",
            description: "Updated description"
          }
        })
        |> render_submit()

      assert html =~ "Photo mise à jour avec succès"

      updated_photo = Photography.get_photo!(photo.id)
      assert updated_photo.title == "Updated Photo Title"
      assert updated_photo.description == "Updated description"
    end

    test "shows validation errors", %{conn: conn} do
      album = create_album_with_photos(1)
      photo = List.first(album.photos)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Ouvrir la modal
      view
      |> element(~s|img[phx-click="edit_photo"][phx-value-id="#{photo.id}"]|)
      |> render_click()

      # Soumettre avec titre trop long (> 200 caractères)
      long_title = String.duplicate("a", 201)

      html =
        view
        |> form(~s|form[phx-submit="save_photo"]|, %{
          photo: %{title: long_title}
        })
        |> render_submit()

      assert html =~ "should be at most 200 character" or html =~ "au plus 200"
    end
  end

  describe "photo reordering" do
    setup :register_and_log_in_user

    test "starts reordering mode", %{conn: conn} do
      album = create_album_with_photos(3)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      html =
        view
        |> element("button[phx-click=\"start_reordering\"]")
        |> render_click()

      # Vérifier que le mode réorganisation est actif
      assert html =~ "Glissez-déposez les photos"
      assert html =~ "Enregistrer l&#39;ordre"
      assert html =~ "Annuler"
      assert has_element?(view, "#photos-grid[data-reordering=\"true\"]")
    end

    test "cancels reordering mode", %{conn: conn} do
      album = create_album_with_photos(3)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Activer le mode réorganisation
      view
      |> element("button[phx-click=\"start_reordering\"]")
      |> render_click()

      # Annuler
      html =
        view
        |> element("button[phx-click=\"cancel_reordering\"]")
        |> render_click()

      # Vérifier que le mode est désactivé
      refute html =~ "Glissez-déposez les photos"
      refute html =~ "Enregistrer l&#39;ordre"
      assert has_element?(view, "button[phx-click=\"start_reordering\"]")
    end

    test "saves photo order", %{conn: conn} do
      album = create_album_with_photos(3)
      photos = album.photos

      # IDs dans l'ordre initial
      [photo1, photo2, photo3] = Enum.sort_by(photos, & &1.display_order)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Activer le mode réorganisation
      view
      |> element("button[phx-click=\"start_reordering\"]")
      |> render_click()

      # Inverser l'ordre: [3, 2, 1]
      new_order = [photo3.id, photo2.id, photo1.id]

      # Simuler le drag-and-drop
      view
      |> render_hook("reorder_photos", %{photo_ids: new_order})

      # Sauvegarder l'ordre
      html =
        view
        |> element("button[phx-click=\"save_photo_order\"]")
        |> render_click()

      assert html =~ "Ordre de 3 photo(s) sauvegardé"

      # Vérifier que l'ordre a été mis à jour en base
      updated_album = Photography.get_album!(album.id, preload: [:photos])
      sorted_photos = Enum.sort_by(updated_album.photos, & &1.display_order)

      assert Enum.at(sorted_photos, 0).id == photo3.id
      assert Enum.at(sorted_photos, 1).id == photo2.id
      assert Enum.at(sorted_photos, 2).id == photo1.id

      # Vérifier les display_order
      assert Enum.at(sorted_photos, 0).display_order == 0
      assert Enum.at(sorted_photos, 1).display_order == 1
      assert Enum.at(sorted_photos, 2).display_order == 2
    end

    test "cover photo is always first photo by display_order", %{conn: conn} do
      album = create_album_with_photos(3)
      photos = album.photos

      [photo1, photo2, photo3] = Enum.sort_by(photos, & &1.display_order)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Activer le mode réorganisation
      view
      |> element("button[phx-click=\"start_reordering\"]")
      |> render_click()

      # Mettre photo3 en première position
      new_order = [photo3.id, photo1.id, photo2.id]

      view
      |> render_hook("reorder_photos", %{photo_ids: new_order})

      view
      |> element("button[phx-click=\"save_photo_order\"]")
      |> render_click()

      # Vérifier que photo3 est maintenant la photo de couverture
      updated_album = Photography.get_album!(album.id, preload: [:photos])
      cover_photo = Enum.min_by(updated_album.photos, & &1.display_order)

      assert cover_photo.id == photo3.id
      assert cover_photo.display_order == 0
    end

    test "reordering mode hides edit and delete buttons", %{conn: conn} do
      album = create_album_with_photos(2)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # En mode normal, les boutons de photo doivent être présents
      assert has_element?(view, "button[phx-click=\"edit_photo\"]", "Modifier")
      assert has_element?(view, "button[phx-click=\"delete_photo\"]", "Supprimer")

      # Activer le mode réorganisation
      html =
        view
        |> element("button[phx-click=\"start_reordering\"]")
        |> render_click()

      # Les boutons de photo ne doivent plus être visibles
      # (mais le formulaire d'album reste visible avec son bouton "Enregistrer")
      refute html =~ "phx-click=\"edit_photo\""
      refute html =~ "phx-click=\"delete_photo\""
    end

    test "displays position badges in reordering mode", %{conn: conn} do
      album = create_album_with_photos(3)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Activer le mode réorganisation
      html =
        view
        |> element("button[phx-click=\"start_reordering\"]")
        |> render_click()

      # Les badges de position doivent être affichés (1, 2, 3)
      # They're in div with class containing the position number
      assert html =~ "1\n                      </div>"
      assert html =~ "2\n                      </div>"
      assert html =~ "3\n                      </div>"
    end
  end

  describe "photo title display" do
    setup :register_and_log_in_user

    test "displays photo title when present", %{conn: conn} do
      album = create_album()
      create_photo(album: album, title: "Beautiful Sunset")

      {:ok, _view, html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      assert html =~ "Beautiful Sunset"
    end

    test "handles nil photo title correctly", %{conn: conn} do
      album = create_album()
      create_photo(album: album, title: nil)

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # Ne doit pas crasher avec BadBooleanError
      assert render(view)
    end

    test "hides photo title in reordering mode", %{conn: conn} do
      album = create_album()
      create_photo(album: album, title: "Test Title")

      {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")

      # En mode normal, le titre est visible
      assert render(view) =~ "Test Title"

      # Activer le mode réorganisation
      html =
        view
        |> element("button[phx-click=\"start_reordering\"]")
        |> render_click()

      # Le titre ne devrait plus être dans le overlay (mais peut être dans alt)
      refute html =~ "bg-black bg-opacity-60.*Test Title"
    end
  end

  # Helper pour créer et authentifier un utilisateur admin
end
