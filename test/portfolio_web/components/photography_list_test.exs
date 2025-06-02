defmodule PortfolioWeb.PhotographyListTest do
  use PortfolioWeb.ConnCase
  alias PortfolioWeb.Components.PhotographyList

  describe "chapter_image/1" do
    test "returns correct image paths for known chapters" do
      string = "amvcc"
      assert PhotographyList.chapter_image(string) == "/images/photography/#{string}.webp"
    end

    test "returns empty string for chapters without image" do
      assert PhotographyList.chapter_image("") == ""
      assert PhotographyList.chapter_image(nil) == ""
    end
  end
end
