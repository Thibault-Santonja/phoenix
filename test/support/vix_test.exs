defmodule Portfolio.VixTest do
  @moduledoc """
  Test suite to verify libvips and Vix installation.
  This ensures that the image processing infrastructure is properly configured.
  """
  use ExUnit.Case, async: true

  describe "libvips installation" do
    test "Vix can retrieve libvips version" do
      version = Vix.Vips.version()
      assert is_binary(version)
      assert String.match?(version, ~r/\d+\.\d+/)
    end
  end

  describe "basic image operations" do
    @tag :skip
    test "can create a test image and get dimensions" do
      # This test is skipped until we have test fixtures
      # It will be used to verify basic image processing
      assert true
    end
  end
end
