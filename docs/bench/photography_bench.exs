# Benchmarks for Photography module critical operations
#
# Run with: mix run bench/photography_bench.exs
#
# These benchmarks validate the performance optimizations mentioned
# in the code review, particularly:
# - photo_count optimization (aggregate vs preload)
# - reorder optimization (single CASE WHEN query vs N updates)

Mix.install([
  {:benchee, "~> 1.3"},
  {:benchee_html, "~> 1.0"}
])

# Start the application to access Repo and modules
{:ok, _} = Application.ensure_all_started(:portfolio)

alias Portfolio.Photography
alias Portfolio.Photography.Repositories.{AlbumRepository, PhotoRepository}
alias Portfolio.Repo

# Setup: Create test data
IO.puts("Setting up test data...")

# Clean up any existing test data
Repo.delete_all(Portfolio.Photography.Photo)
Repo.delete_all(Portfolio.Photography.Album)

# Create test album
{:ok, album} =
  AlbumRepository.insert(%{
    title: "Benchmark Album",
    description: "Album for performance testing",
    type: :music,
    date_prise_vue: ~D[2025-01-01],
    published: true
  })

# Create varying numbers of photos for different scenarios
photos_10 =
  Enum.map(1..10, fn i ->
    {:ok, photo} =
      PhotoRepository.insert(%{
        album_id: album.id,
        original_filename: "photo_#{i}.jpg",
        file_path: "/test/photo_#{i}.jpg",
        display_order: i - 1
      })

    photo
  end)

photos_50 =
  Enum.map(11..60, fn i ->
    {:ok, photo} =
      PhotoRepository.insert(%{
        album_id: album.id,
        original_filename: "photo_#{i}.jpg",
        file_path: "/test/photo_#{i}.jpg",
        display_order: i - 1
      })

    photo
  end)

photos_100 =
  Enum.map(61..160, fn i ->
    {:ok, photo} =
      PhotoRepository.insert(%{
        album_id: album.id,
        original_filename: "photo_#{i}.jpg",
        file_path: "/test/photo_#{i}.jpg",
        display_order: i - 1
      })

    photo
  end)

all_photos = photos_10 ++ photos_50 ++ photos_100
IO.puts("Created #{length(all_photos)} test photos")

# Benchmark 1: Photo count optimization
# Compares with_photo_count (aggregate) vs preloading all photos
IO.puts("\n=== Benchmark 1: Photo Count Optimization ===\n")

Benchee.run(
  %{
    "with_photo_count (optimized)" => fn ->
      AlbumRepository.list(with_photo_count: true, limit: 30)
    end,
    "preload photos then count" => fn ->
      albums = AlbumRepository.list(preload: [:photos], limit: 30)
      Enum.map(albums, fn album -> %{album | photo_count: length(album.photos)} end)
    end
  },
  time: 5,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.HTML, file: "docs/bench/results/photo_count.html"}
  ]
)

# Benchmark 2: Reorder optimization
# Compares single CASE WHEN query vs N individual updates
IO.puts("\n=== Benchmark 2: Reorder Optimization ===\n")

# Helper function for N updates approach (old way)
defmodule LegacyReorder do
  import Ecto.Query
  alias Portfolio.Repo
  alias Portfolio.Photography.Photo

  def reorder_n_queries(photo_ids) do
    Repo.transaction(fn ->
      Enum.with_index(photo_ids)
      |> Enum.each(fn {photo_id, index} ->
        from(p in Photo, where: p.id == ^photo_id)
        |> Repo.update_all(set: [display_order: index, updated_at: DateTime.utc_now()])
      end)
    end)
  end
end

# Test with different photo counts
photo_ids_10 = Enum.map(photos_10, & &1.id)
photo_ids_50 = Enum.take(photos_50, 50) |> Enum.map(& &1.id)
photo_ids_100 = Enum.take(photos_100, 100) |> Enum.map(& &1.id)

Benchee.run(
  %{
    "10 photos - CASE WHEN (optimized)" => fn ->
      PhotoRepository.reorder(album.id, Enum.shuffle(photo_ids_10))
    end,
    "10 photos - N queries (legacy)" => fn ->
      LegacyReorder.reorder_n_queries(Enum.shuffle(photo_ids_10))
    end,
    "50 photos - CASE WHEN (optimized)" => fn ->
      PhotoRepository.reorder(album.id, Enum.shuffle(photo_ids_50))
    end,
    "50 photos - N queries (legacy)" => fn ->
      LegacyReorder.reorder_n_queries(Enum.shuffle(photo_ids_50))
    end,
    "100 photos - CASE WHEN (optimized)" => fn ->
      PhotoRepository.reorder(album.id, Enum.shuffle(photo_ids_100))
    end,
    "100 photos - N queries (legacy)" => fn ->
      LegacyReorder.reorder_n_queries(Enum.shuffle(photo_ids_100))
    end
  },
  time: 5,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.HTML, file: "docs/bench/results/reorder.html"}
  ]
)

# Benchmark 3: List albums with sorting
IO.puts("\n=== Benchmark 3: Album Listing with Sorting ===\n")

Benchee.run(
  %{
    "sort by title" => fn ->
      Photography.list_albums(order_by: [asc: :title], limit: 30, with_photo_count: true)
    end,
    "sort by date" => fn ->
      Photography.list_albums(
        order_by: [desc: :date_prise_vue],
        limit: 30,
        with_photo_count: true
      )
    end,
    "sort by photo_count" => fn ->
      Photography.list_albums(order_by: [desc: :photo_count], limit: 30, with_photo_count: true)
    end
  },
  time: 5,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.HTML, file: "docs/bench/results/album_listing.html"}
  ]
)

# Cleanup
IO.puts("\nCleaning up test data...")
Repo.delete_all(Portfolio.Photography.Photo)
Repo.delete_all(Portfolio.Photography.Album)

IO.puts("\n✅ Benchmarks complete! Check bench/results/ for HTML reports.")
