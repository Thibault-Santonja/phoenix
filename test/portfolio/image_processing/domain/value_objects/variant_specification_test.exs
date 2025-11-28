defmodule Portfolio.ImageProcessing.Domain.ValueObjects.VariantSpecificationTest do
  use ExUnit.Case, async: true

  alias Portfolio.ImageProcessing.Domain.ValueObjects.VariantSpecification

  doctest VariantSpecification

  describe "new/5" do
    test "creates valid specification with webp format" do
      assert {:ok, spec} = VariantSpecification.new(:thumbnail, 400, 75, :webp, 4)
      assert spec.name == :thumbnail
      assert spec.width == 400
      assert spec.quality == 75
      assert spec.format == :webp
      assert spec.effort == 4
    end

    test "creates valid specification with avif format" do
      assert {:ok, spec} = VariantSpecification.new(:large, 1920, 85, :avif, 6)
      assert spec.name == :large
      assert spec.width == 1920
      assert spec.quality == 85
      assert spec.format == :avif
      assert spec.effort == 6
    end

    test "creates valid specification with jpeg format" do
      assert {:ok, spec} = VariantSpecification.new(:medium, 960, 80, :jpeg, 5)
      assert spec.name == :medium
      assert spec.format == :jpeg
    end

    test "accepts minimum width of 1" do
      assert {:ok, spec} = VariantSpecification.new(:tiny, 1, 75, :webp, 4)
      assert spec.width == 1
    end

    test "accepts minimum quality of 1" do
      assert {:ok, spec} = VariantSpecification.new(:low, 400, 1, :webp, 4)
      assert spec.quality == 1
    end

    test "accepts maximum quality of 100" do
      assert {:ok, spec} = VariantSpecification.new(:high, 400, 100, :webp, 4)
      assert spec.quality == 100
    end

    test "accepts minimum effort of 0" do
      assert {:ok, spec} = VariantSpecification.new(:fast, 400, 75, :webp, 0)
      assert spec.effort == 0
    end

    test "accepts maximum effort for webp (6)" do
      assert {:ok, _spec} = VariantSpecification.new(:slow, 400, 75, :webp, 6)
    end

    test "accepts maximum effort for avif (9)" do
      assert {:ok, _spec} = VariantSpecification.new(:slow, 400, 75, :avif, 9)
    end

    test "accepts maximum effort for jpeg (9)" do
      assert {:ok, _spec} = VariantSpecification.new(:slow, 400, 75, :jpeg, 9)
    end

    test "returns error for zero width" do
      assert {:error, :invalid_width} = VariantSpecification.new(:bad, 0, 75, :webp, 4)
    end

    test "returns error for negative width" do
      assert {:error, :invalid_width} = VariantSpecification.new(:bad, -100, 75, :webp, 4)
    end

    test "returns error for nil width" do
      assert {:error, :invalid_width} = VariantSpecification.new(:bad, nil, 75, :webp, 4)
    end

    test "returns error for quality 0" do
      assert {:error, :invalid_quality} = VariantSpecification.new(:bad, 400, 0, :webp, 4)
    end

    test "returns error for quality 101" do
      assert {:error, :invalid_quality} = VariantSpecification.new(:bad, 400, 101, :webp, 4)
    end

    test "returns error for negative quality" do
      assert {:error, :invalid_quality} = VariantSpecification.new(:bad, 400, -10, :webp, 4)
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = VariantSpecification.new(:bad, 400, 75, :png, 4)
    end

    test "returns error for nil format" do
      assert {:error, :invalid_format} = VariantSpecification.new(:bad, 400, 75, nil, 4)
    end

    test "returns error for effort exceeding webp max (7)" do
      assert {:error, :invalid_effort} = VariantSpecification.new(:bad, 400, 75, :webp, 7)
    end

    test "returns error for effort exceeding avif max (10)" do
      assert {:error, :invalid_effort} = VariantSpecification.new(:bad, 400, 75, :avif, 10)
    end

    test "returns error for negative effort" do
      assert {:error, :invalid_effort} = VariantSpecification.new(:bad, 400, 75, :webp, -1)
    end

    test "returns error for nil effort" do
      assert {:error, :invalid_effort} = VariantSpecification.new(:bad, 400, 75, :webp, nil)
    end

    test "returns error for float width" do
      assert {:error, :invalid_width} = VariantSpecification.new(:bad, 400.5, 75, :webp, 4)
    end

    test "returns error for string name" do
      assert {:error, :invalid_width} = VariantSpecification.new("thumbnail", 400, 75, :webp, 4)
    end
  end

  describe "new!/5" do
    test "creates valid specification" do
      spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)
      assert spec.name == :thumbnail
      assert spec.width == 400
    end

    test "raises ArgumentError for invalid width" do
      assert_raise ArgumentError, "Invalid variant specification: invalid_width", fn ->
        VariantSpecification.new!(:bad, 0, 75, :webp, 4)
      end
    end

    test "raises ArgumentError for invalid quality" do
      assert_raise ArgumentError, "Invalid variant specification: invalid_quality", fn ->
        VariantSpecification.new!(:bad, 400, 150, :webp, 4)
      end
    end

    test "raises ArgumentError for invalid format" do
      assert_raise ArgumentError, "Invalid variant specification: invalid_format", fn ->
        VariantSpecification.new!(:bad, 400, 75, :bmp, 4)
      end
    end

    test "raises ArgumentError for invalid effort" do
      assert_raise ArgumentError, "Invalid variant specification: invalid_effort", fn ->
        VariantSpecification.new!(:bad, 400, 75, :webp, 10)
      end
    end
  end

  describe "from_config/1" do
    test "creates specification from valid config map" do
      config = %{name: :thumbnail, width: 400, quality: 75, format: :webp, effort: 4}
      assert {:ok, spec} = VariantSpecification.from_config(config)
      assert spec.name == :thumbnail
      assert spec.width == 400
    end

    test "returns error for missing required fields" do
      config = %{name: :thumbnail, width: 400}
      assert {:error, :missing_required_fields} = VariantSpecification.from_config(config)
    end

    test "returns error for empty map" do
      assert {:error, :missing_required_fields} = VariantSpecification.from_config(%{})
    end

    test "returns error for config with invalid values" do
      config = %{name: :bad, width: 0, quality: 75, format: :webp, effort: 4}
      assert {:error, :invalid_width} = VariantSpecification.from_config(config)
    end

    test "returns error for list input" do
      assert {:error, :missing_required_fields} = VariantSpecification.from_config([])
    end

    test "returns error for nil input" do
      assert {:error, :missing_required_fields} = VariantSpecification.from_config(nil)
    end
  end

  describe "filename/1" do
    test "generates filename for webp variant" do
      spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)
      assert VariantSpecification.filename(spec) == "thumbnail.webp"
    end

    test "generates filename for avif variant" do
      spec = VariantSpecification.new!(:large, 1920, 85, :avif, 6)
      assert VariantSpecification.filename(spec) == "large.avif"
    end

    test "generates filename for jpeg variant" do
      spec = VariantSpecification.new!(:medium, 960, 80, :jpeg, 5)
      assert VariantSpecification.filename(spec) == "medium.jpg"
    end

    test "generates filename with complex name" do
      spec = VariantSpecification.new!(:large_webp_2x, 1920, 85, :webp, 4)
      assert VariantSpecification.filename(spec) == "large_webp_2x.webp"
    end
  end

  describe "name/1" do
    test "returns name of specification" do
      spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)
      assert VariantSpecification.name(spec) == :thumbnail
    end

    test "returns name for different variants" do
      for name <- [:small, :medium, :large, :xlarge] do
        spec = VariantSpecification.new!(name, 400, 75, :webp, 4)
        assert VariantSpecification.name(spec) == name
      end
    end
  end

  describe "integration scenarios" do
    test "all formats can be used to create valid specifications" do
      for format <- [:webp, :avif, :jpeg] do
        assert {:ok, spec} = VariantSpecification.new(:test, 400, 75, format, 4)
        assert spec.format == format
      end
    end

    test "specifications with same parameters are equal" do
      {:ok, spec1} = VariantSpecification.new(:thumbnail, 400, 75, :webp, 4)
      {:ok, spec2} = VariantSpecification.new(:thumbnail, 400, 75, :webp, 4)
      assert spec1 == spec2
    end

    test "specifications with different names are not equal" do
      {:ok, spec1} = VariantSpecification.new(:thumbnail, 400, 75, :webp, 4)
      {:ok, spec2} = VariantSpecification.new(:small, 400, 75, :webp, 4)
      refute spec1 == spec2
    end

    test "typical variant sizes work correctly" do
      variants = [
        {:thumbnail, 400},
        {:small, 640},
        {:medium, 960},
        {:large, 1280},
        {:xlarge, 1920}
      ]

      for {name, width} <- variants do
        assert {:ok, _spec} = VariantSpecification.new(name, width, 80, :webp, 4)
      end
    end
  end
end
