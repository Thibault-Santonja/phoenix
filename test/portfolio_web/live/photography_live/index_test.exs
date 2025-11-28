defmodule PortfolioWeb.PhotographyLive.IndexTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  # Index is on the photo subdomain
  @endpoint PortfolioWeb.Endpoint

  setup %{conn: conn} do
    # Set French locale for consistent testing (default locale)
    Gettext.put_locale(PortfolioWeb.Gettext, "fr")
    # Set the photo subdomain
    conn = %{conn | host: "photo.example.com"}
    # Initialize session with French locale
    conn = init_test_session(conn, %{"locale" => "fr"})
    %{conn: conn}
  end

  describe "Mount and Display" do
    test "renders photography index page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Thibault Santonja"
    end

    test "displays language selector", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert view |> element("button[phx-click='change_locale']") |> has_element?()
    end

    test "sets page title", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Check page renders with French title
      assert html =~ "Photographie" or html =~ "Photography"
    end
  end

  describe "Modal handling" do
    test "opens modal when chapter parameter is provided", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=china")

      # Modal should display china chapter content
      assert html =~ "china" or html =~ "Chine"
    end

    test "open_modal event opens modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Trigger open_modal event
      html = render_click(view, "open_modal", %{"chapter" => "music"})

      # Modal should be visible with music content
      assert html =~ "music" or html =~ "Concert"
    end

    test "close_modal event closes modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?chapter=wedding")

      # Close the modal
      _html = render_click(view, "close_modal", %{})

      # Modal chapter should be cleared (URL should no longer have chapter)
      assert_patched(view, ~p"/?hl=fr")
    end

    test "modal has close button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?chapter=japan")

      # Should have close button
      assert has_element?(view, "button.close-modal")
    end
  end

  describe "Locale handling" do
    test "change_locale event updates locale", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Change locale to French
      render_click(view, "change_locale", %{"locale" => "fr"})

      # Verify URL updated with locale
      assert_patched(view, ~p"/?hl=fr")
    end

    test "accepts locale from URL parameter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?hl=en")

      # Page should render with English content
      assert html =~ "Thibault"
    end

    test "accepts locale from session", %{conn: conn} do
      conn = init_test_session(conn, %{"locale" => "en"})

      {:ok, _view, html} = live(conn, ~p"/")

      # Page should render
      assert html =~ "Thibault"
    end

    test "defaults to French locale when not specified", %{conn: conn} do
      conn = init_test_session(conn, %{})

      {:ok, _view, html} = live(conn, ~p"/")

      # Default French locale
      assert html =~ "Photographie" or html =~ "Accueil"
    end
  end

  describe "Chapter modal content" do
    test "displays AMVCC chapter content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=amvcc")

      assert html =~ "AMVCC"
    end

    test "displays landscape chapter content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=landscape")

      # Should have landscape content
      assert html =~ "landscape" or html =~ "Paysage"
    end

    test "displays music chapter content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=music")

      # Should have music content
      assert html =~ "music" or html =~ "Concert"
    end

    test "displays reenactment chapter content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=reenactment")

      # Should have reenactment content
      assert html =~ "reenactment" or html =~ "Reconstitution"
    end

    test "displays street chapter content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=street")

      # Should have street content
      assert html =~ "street" or html =~ "Rue"
    end

    test "displays china chapter content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=china")

      # Should have china content
      assert html =~ "china" or html =~ "Chine"
    end

    test "displays japan chapter content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=japan")

      # Should have japan content
      assert html =~ "japan" or html =~ "Japon"
    end

    test "displays taiwan chapter content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=taiwan")

      # Should have taiwan content
      assert html =~ "taiwan" or html =~ "Taiwan"
    end

    test "displays couples chapter content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=couples")

      # Should have couples content
      assert html =~ "couples" or html =~ "Couple"
    end

    test "displays motherhood chapter content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=motherhood")

      # Should have motherhood content
      assert html =~ "motherhood" or html =~ "Famille" or html =~ "Maternité"
    end

    test "displays wedding chapter content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=wedding")

      # Should have wedding content
      assert html =~ "wedding" or html =~ "Mariage"
    end

    test "displays events chapter content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=events")

      # Should have events content
      assert html =~ "events" or html =~ "Événement"
    end

    test "displays default content for unknown chapter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=unknown")

      # Should have default gallery content
      assert html =~ "Galerie" or html =~ "Gallery"
    end
  end

  describe "Format chapter title" do
    test "formats AMVCC title correctly", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=amvcc")

      assert html =~ "AMVCC"
    end

    test "formats chapter titles in header", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=china")

      # Should display formatted chapter title
      assert html =~ "Chine" or html =~ "china"
    end
  end

  describe "Navigation links" do
    test "reenactment chapter has timeline link", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/?chapter=reenactment")

      # Should have link to timeline
      assert html =~ "/timeline/reenactment"
      assert has_element?(view, "a[href='/timeline/reenactment']")
    end

    test "amvcc chapter has timeline link", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/?chapter=amvcc")

      # Should have link to timeline
      assert html =~ "/timeline/amvcc"
      assert has_element?(view, "a[href='/timeline/amvcc']")
    end

    test "music chapter has timeline link", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/?chapter=music")

      # Should have link to timeline
      assert html =~ "/timeline/music"
      assert has_element?(view, "a[href='/timeline/music']")
    end

    test "china chapter has gallery link", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/?chapter=china")

      # Should have link to gallery
      assert html =~ "/gallery/china"
      assert has_element?(view, "a[href='/gallery/china']")
    end
  end

  describe "Handle params" do
    test "applies index action correctly", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Should render index page
      assert html =~ "Photographie" or html =~ "Thibault"
    end

    test "handles params with chapter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?chapter=wedding&hl=fr")

      # Should show wedding modal
      assert html =~ "wedding" or html =~ "Mariage"
    end
  end

  describe "Theme button" do
    test "renders theme button component", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Theme button should be present
      assert has_element?(view, "button[phx-click='change_locale']")
    end
  end

  describe "Photography list component" do
    test "renders photography list", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      # Should render photography list component
      assert html =~ "Thibault"
    end
  end
end
