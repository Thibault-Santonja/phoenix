# Benchmark pour l'upload de photos
#
# Usage:
#   mix run bench/photography/photo_upload_bench.exs
#
# Résultats HTML:
#   bench/results/photo_upload.html

# Setup du repo pour les benchmarks
Mix.install([])

# Démarrer l'application
{:ok, _} = Application.ensure_all_started(:portfolio)

alias Portfolio.Photography
alias Portfolio.Repo

# Helper pour créer un album de test
defp create_test_album do
  attrs = %{
    title: "Benchmark Album #{:rand.uniform(100_000)}",
    type: "wedding",
    date_prise_vue: ~D[2024-01-01],
    published: false
  }

  {:ok, album} = Photography.create_album(attrs)
  album
end

# Helper pour créer un faux upload
defp create_upload(index \\ 1) do
  %{
    path: "/tmp/bench_photo_#{index}.jpg",
    filename: "photo_#{index}.jpg",
    content_type: "image/jpeg"
  }
end

# Helper pour créer plusieurs uploads
defp create_uploads(count) do
  Enum.map(1..count, &create_upload/1)
end

# Nettoyage avant les benchmarks
Repo.query!("TRUNCATE TABLE photos CASCADE")
Repo.query!("TRUNCATE TABLE albums CASCADE")

IO.puts("\n🔥 Photo Upload Benchmarks\n")
IO.puts("=" |> String.duplicate(50))
IO.puts("Mesure la performance d'upload de photos en batch")
IO.puts("Target: < 500ms pour 10 photos\n")

Benchee.run(
  %{
    "upload 1 photo" => fn album ->
      Photography.upload_photos(album.slug, create_uploads(1))
    end,
    "upload 5 photos" => fn album ->
      Photography.upload_photos(album.slug, create_uploads(5))
    end,
    "upload 10 photos" => fn album ->
      Photography.upload_photos(album.slug, create_uploads(10))
    end,
    "upload 20 photos" => fn album ->
      Photography.upload_photos(album.slug, create_uploads(20))
    end
  },
  before_scenario: fn _ ->
    # Créer un nouvel album pour chaque scénario
    create_test_album()
  end,
  after_scenario: fn album ->
    # Nettoyer après chaque scénario
    Photography.delete_album(album)
    :ok
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.HTML, file: "bench/results/photo_upload.html"}
  ],
  time: 5,
  memory_time: 2,
  warmup: 1
)
