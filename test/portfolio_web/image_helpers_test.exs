defmodule PortfolioWeb.ImageHelpersTest do
  use ExUnit.Case, async: true

  alias Portfolio.Photography.Photo
  alias PortfolioWeb.ImageHelpers

  describe "image_srcset/1" do
    test "generates srcset from all variants" do
      photo = %Photo{
        variants: %{
          "thumbnail" => "/photos/abc/thumbnail.webp",
          "small" => "/photos/abc/small.webp",
          "medium" => "/photos/abc/medium.webp",
          "large" => "/photos/abc/large.webp"
        }
      }

      srcset = ImageHelpers.image_srcset(photo)

      assert srcset =~ "/photos/abc/thumbnail.webp 320w"
      assert srcset =~ "/photos/abc/small.webp 640w"
      assert srcset =~ "/photos/abc/medium.webp 1024w"
      assert srcset =~ "/photos/abc/large.webp 1920w"
    end

    test "handles partial variants" do
      photo = %Photo{
        variants: %{
          "small" => "/photos/abc/small.webp",
          "large" => "/photos/abc/large.webp"
        }
      }

      srcset = ImageHelpers.image_srcset(photo)

      assert srcset =~ "/photos/abc/small.webp 640w"
      assert srcset =~ "/photos/abc/large.webp 1920w"
      refute srcset =~ "thumbnail"
      refute srcset =~ "medium"
    end

    test "returns empty string when no variants" do
      photo = %Photo{variants: %{}}
      assert ImageHelpers.image_srcset(photo) == ""
    end

    test "returns empty string when variants is nil" do
      photo = %Photo{variants: nil}
      assert ImageHelpers.image_srcset(photo) == ""
    end

    test "orders variants by width" do
      photo = %Photo{
        variants: %{
          "large" => "/photos/abc/large.webp",
          "thumbnail" => "/photos/abc/thumbnail.webp",
          "medium" => "/photos/abc/medium.webp",
          "small" => "/photos/abc/small.webp"
        }
      }

      srcset = ImageHelpers.image_srcset(photo)

      # Should be ordered: thumbnail, small, medium, large
      thumbnail_pos = :binary.match(srcset, "thumbnail") |> elem(0)
      small_pos = :binary.match(srcset, "small") |> elem(0)
      medium_pos = :binary.match(srcset, "medium") |> elem(0)
      large_pos = :binary.match(srcset, "large") |> elem(0)

      assert thumbnail_pos < small_pos
      assert small_pos < medium_pos
      assert medium_pos < large_pos
    end
  end

  describe "get_default_src/1" do
    test "prefers medium variant" do
      photo = %Photo{
        variants: %{
          "thumbnail" => "/photos/abc/thumbnail.webp",
          "small" => "/photos/abc/small.webp",
          "medium" => "/photos/abc/medium.webp",
          "large" => "/photos/abc/large.webp"
        }
      }

      assert ImageHelpers.get_default_src(photo) == "/photos/abc/medium.webp"
    end

    test "falls back to small if medium not available" do
      photo = %Photo{
        variants: %{
          "thumbnail" => "/photos/abc/thumbnail.webp",
          "small" => "/photos/abc/small.webp",
          "large" => "/photos/abc/large.webp"
        }
      }

      assert ImageHelpers.get_default_src(photo) == "/photos/abc/small.webp"
    end

    test "falls back to large if medium and small not available" do
      photo = %Photo{
        variants: %{
          "thumbnail" => "/photos/abc/thumbnail.webp",
          "large" => "/photos/abc/large.webp"
        }
      }

      assert ImageHelpers.get_default_src(photo) == "/photos/abc/large.webp"
    end

    test "falls back to thumbnail if only available" do
      photo = %Photo{
        variants: %{
          "thumbnail" => "/photos/abc/thumbnail.webp"
        }
      }

      assert ImageHelpers.get_default_src(photo) == "/photos/abc/thumbnail.webp"
    end

    test "falls back to file_path when no variants" do
      photo = %Photo{
        file_path: "/uploads/original.jpg",
        variants: %{}
      }

      assert ImageHelpers.get_default_src(photo) == "/uploads/original.jpg"
    end
  end

  describe "thumbnail_url/1" do
    test "returns thumbnail variant URL" do
      photo = %Photo{
        variants: %{
          "thumbnail" => "/photos/abc/thumbnail.webp",
          "small" => "/photos/abc/small.webp"
        }
      }

      assert ImageHelpers.thumbnail_url(photo) == "/photos/abc/thumbnail.webp"
    end

    test "falls back to small if thumbnail not available" do
      photo = %Photo{
        variants: %{
          "small" => "/photos/abc/small.webp",
          "medium" => "/photos/abc/medium.webp"
        }
      }

      assert ImageHelpers.thumbnail_url(photo) == "/photos/abc/small.webp"
    end

    test "falls back to file_path when no variants" do
      photo = %Photo{
        file_path: "/uploads/original.jpg",
        variants: %{}
      }

      assert ImageHelpers.thumbnail_url(photo) == "/uploads/original.jpg"
    end
  end
end
