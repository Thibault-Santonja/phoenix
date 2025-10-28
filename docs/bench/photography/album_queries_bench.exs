# Benchmark pour les requêtes d'albums
#
# Usage:
#   mix run bench/photography/album_queries_bench.exs
#
# Résultats HTML:
#   bench/results/album_queries.html

# Démarrer l'application
{:ok, _} = Application.ensure_all_started(:portfolio)

alias Portfolio.Photography
alias Portfolio.Repo

# Helper pour créer un album avec photos
defp create_album_with_photos(title, photo_count) do
  attrs = %{
    title: title,
    type: "wedding",
    date_prise_vue: ~D[2024-01-01],
    published: true
  }

  {:ok, album} = Photography.create_album(attrs)

  # Créer les photos
  for i <- 1..photo_count do
    photo_attrs = %{
      album_id: album.id,
      original_filename: "photo_#{i}.jpg",
      file_path: "/uploads/photo_#{i}.jpg",
      display_order: i,
      published: true
    }

    Photography.create_photo(photo_attrs)
  end

  album
end

# Setup : Créer 50 albums avec photos
IO.puts("\n📊 Album Queries Benchmarks\n")
IO.puts("=" |> String.duplicate(50))
IO.puts("Setup: Création de 50 albums avec 5 photos chacun...")

# Nettoyage
Repo.query!("TRUNCATE TABLE photos CASCADE")
Repo.query!("TRUNCATE TABLE albums CASCADE")

# Créer les données de test
for i <- 1..50 do
  create_album_with_photos("Album #{i}", 5)
end

# Créer un album spécifique pour les tests de get
test_album = create_album_with_photos("Test Album", 10)

IO.puts("✅ Setup terminé : 50 albums créés")
IO.puts("Target: < 50ms pour list_albums, < 100ms pour get_album\n")

Benchee.run(
  %{
    "list all albums (no preload)" => fn ->
      Photography.list_albums()
    end,
    "list published albums only" => fn ->
      Photography.list_albums(published: true)
    end,
    "list albums with photos preload" => fn ->
      Photography.list_albums(preload: [:photos])
    end,
    "list published by year" => fn ->
      Photography.list_published_albums_by_year()
    end,
    "get album by slug (no preload)" => fn ->
      Photography.get_album_by_slug(test_album.slug)
    end,
    "get album by slug (with photos)" => fn ->
      Photography.get_album_by_slug(test_album.slug, preload: [:photos])
    end,
    "count all albums" => fn ->
      Photography.count_all_albums()
    end,
    "count published albums" => fn ->
      Photography.count_published_albums()
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.HTML, file: "bench/results/album_queries.html"}
  ],
  time: 5,
  memory_time: 2,
  warmup: 1
)

# Nettoyage
IO.puts("\n🧹 Nettoyage des données de test...")
Repo.query!("TRUNCATE TABLE photos CASCADE")
Repo.query!("TRUNCATE TABLE albums CASCADE")
