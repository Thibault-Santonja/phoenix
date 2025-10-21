# Benchmark pour le réordonnancement de photos
#
# Usage:
#   mix run bench/photography/photo_reorder_bench.exs
#
# Résultats HTML:
#   bench/results/photo_reorder.html

# Démarrer l'application
{:ok, _} = Application.ensure_all_started(:portfolio)

alias Portfolio.Photography
alias Portfolio.Repo

# Helper pour créer un album avec N photos
defp create_album_with_photos(photo_count) do
  attrs = %{
    title: "Benchmark Album #{photo_count} photos",
    type: "wedding",
    date_prise_vue: ~D[2024-01-01],
    published: true
  }

  {:ok, album} = Photography.create_album(attrs)

  # Créer les photos
  photo_ids =
    for i <- 1..photo_count do
      photo_attrs = %{
        album_id: album.id,
        original_filename: "photo_#{i}.jpg",
        file_path: "/uploads/photo_#{i}.jpg",
        display_order: i,
        published: true
      }

      {:ok, photo} = Photography.create_photo(photo_attrs)
      photo.id
    end

  {album, photo_ids}
end

IO.puts("\n🔄 Photo Reorder Benchmarks\n")
IO.puts("=" |> String.duplicate(50))
IO.puts("Mesure la performance du réordonnancement de photos")
IO.puts("Target: < 200ms pour 50 photos\n")

# Nettoyage
Repo.query!("TRUNCATE TABLE photos CASCADE")
Repo.query!("TRUNCATE TABLE albums CASCADE")

Benchee.run(
  %{
    "reorder 10 photos" => fn {album, photo_ids} ->
      shuffled = Enum.shuffle(photo_ids)
      Photography.reorder_photos(album.id, shuffled)
    end,
    "reorder 25 photos" => fn {album, photo_ids} ->
      shuffled = Enum.shuffle(photo_ids)
      Photography.reorder_photos(album.id, shuffled)
    end,
    "reorder 50 photos" => fn {album, photo_ids} ->
      shuffled = Enum.shuffle(photo_ids)
      Photography.reorder_photos(album.id, shuffled)
    end,
    "reorder 100 photos" => fn {album, photo_ids} ->
      shuffled = Enum.shuffle(photo_ids)
      Photography.reorder_photos(album.id, shuffled)
    end
  },
  inputs: %{
    "10 photos" => create_album_with_photos(10),
    "25 photos" => create_album_with_photos(25),
    "50 photos" => create_album_with_photos(50),
    "100 photos" => create_album_with_photos(100)
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.HTML, file: "bench/results/photo_reorder.html"}
  ],
  time: 5,
  memory_time: 2,
  warmup: 1
)

# Nettoyage
IO.puts("\n🧹 Nettoyage des données de test...")
Repo.query!("TRUNCATE TABLE photos CASCADE")
Repo.query!("TRUNCATE TABLE albums CASCADE")
