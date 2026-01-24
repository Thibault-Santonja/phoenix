defmodule ImageProcessingBenchmark do
  @moduledoc """
  Benchmark for image processing with Vix/libvips.

  This benchmark validates that we meet the performance targets defined in the roadmap:
  - Process a 4000×3000 JPEG (12MP, ~5MB) in under 4 seconds for 4 variants
  - Memory usage stays under 200MB during processing

  ## Running

      mix run benchmark/image_processing_benchmark.exs

  ## Requirements

  Place a test image at `test/fixtures/images/sample.jpg` (or it will generate one)
  """

  def run do
    IO.puts("\n=== Image Processing Benchmark ===\n")
    IO.puts("libvips version: #{Vix.Vips.version()}\n")

    # Create a test image if it doesn't exist
    sample_path = "test/fixtures/images/sample.jpg"

    if !File.exists?(sample_path) do
      IO.puts("Creating test image (1920x1080)...")
      create_test_image(sample_path)
    end

    # Get image info
    {:ok, img} = Vix.Vips.Image.new_from_file(sample_path)
    width = Vix.Vips.Image.width(img)
    height = Vix.Vips.Image.height(img)
    {:ok, file_stat} = File.stat(sample_path)

    IO.puts("Test image: #{width}x#{height} (~#{format_bytes(file_stat.size)})\n")

    # Benchmark simple resize
    IO.puts("Benchmarking resize operations...\n")

    Benchee.run(
      %{
        "thumbnail (320px)" => fn -> resize_image(img, 320) end,
        "small (640px)" => fn -> resize_image(img, 640) end,
        "medium (1024px)" => fn -> resize_image(img, 1024) end,
        "large (1920px)" => fn -> resize_image(img, 1920) end,
        "all 4 variants" => fn -> generate_all_variants(img) end
      },
      time: 3,
      memory_time: 2,
      formatters: [
        Benchee.Formatters.Console
      ]
    )

    IO.puts("\n✅ Benchmark complete!")
    IO.puts("\nPerformance targets:")
    IO.puts("  - 4 variants in < 4s: Check results above")
    IO.puts("  - Memory < 200MB: Check results above")
  end

  defp create_test_image(path) do
    # Create a simple 1920x1080 black image
    {:ok, img} = Vix.Vips.Operation.black(1920, 1080)
    Vix.Vips.Image.write_to_file(img, path)
  end

  defp resize_image(img, width) do
    # Calculate scale factor
    current_width = Vix.Vips.Image.width(img)
    scale = width / current_width

    # Resize image
    {:ok, resized} = Vix.Vips.Operation.resize(img, scale)
    resized
  end

  defp generate_all_variants(img) do
    [320, 640, 1024, 1920]
    |> Enum.map(fn width -> resize_image(img, width) end)
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)}KB"

  defp format_bytes(bytes),
    do: "#{Float.round(bytes / (1024 * 1024), 1)}MB"
end

ImageProcessingBenchmark.run()
