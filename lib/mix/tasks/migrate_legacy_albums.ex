defmodule Mix.Tasks.MigrateLegacyAlbums do
  @moduledoc """
  Migre les albums existants depuis la structure legacy vers la nouvelle base de données.

  Usage:
      mix migrate_legacy_albums

  Ce script migre:
  - priv/static/images/photography/20250614_MALN/ -> Album "Minuit avant la Nuit" (22 photos)
  - priv/static/images/photography/20250621_Bours/ -> Album "Donjon de Bours" (10 photos)
  - priv/static/images/photography/gallery/*.webp -> Albums individuels (15 photos)
  """

  use Mix.Task

  alias Portfolio.Photography
  alias Portfolio.Repo

  require Logger

  @shortdoc "Migrate legacy albums to new database structure"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Logger.info("Starting legacy album migration...")

    # Migrate MALN album
    migrate_maln_album()

    # Migrate Bours album
    migrate_bours_album()

    # Migrate gallery single-image albums
    migrate_gallery_albums()

    Logger.info("Migration completed successfully!")
  end

  defp migrate_maln_album do
    Logger.info("Migrating MALN album...")

    album_attrs = %{
      title: "Minuit avant la Nuit",
      slug: "minuit-avant-la-nuit",
      type: :reenactment,
      description:
        "Festival médiéval fantastique à Lagny-sur-Marne. Une soirée magique avec reconstitutions historiques, spectacles et ambiance médiévale.",
      date_prise_vue: ~D[2025-06-14],
      published: true
    }

    case Photography.create_album(album_attrs) do
      {:ok, album} ->
        Logger.info("Created album: #{album.title}")

        source_dir = "priv/static/images/photography/20250614_MALN"
        migrate_photos_from_directory(album, source_dir)

      {:error, changeset} ->
        Logger.error("Failed to create MALN album: #{inspect(changeset.errors)}")
    end
  end

  defp migrate_bours_album do
    Logger.info("Migrating Bours album...")

    album_attrs = %{
      title: "Donjon de Bours",
      slug: "donjon-de-bours",
      type: :reenactment,
      description:
        "Visite du Donjon de Bours, forteresse médiévale du XIVe siècle dans le Pas-de-Calais. Architecture militaire et vestiges historiques.",
      date_prise_vue: ~D[2025-06-21],
      published: true
    }

    case Photography.create_album(album_attrs) do
      {:ok, album} ->
        Logger.info("Created album: #{album.title}")

        source_dir = "priv/static/images/photography/20250621_Bours"
        migrate_photos_from_directory(album, source_dir)

      {:error, changeset} ->
        Logger.error("Failed to create Bours album: #{inspect(changeset.errors)}")
    end
  end

  defp migrate_gallery_albums do
    Logger.info("Migrating gallery albums...")

    gallery_dir = "priv/static/images/photography/gallery"

    # Mapping filename -> {title, category, date}
    gallery_mapping = %{
      "2023-12-09_couples.webp" => {"Couples - Décembre 2023", "couples", ~D[2023-12-09]},
      "2023-12-17_amvcc.webp" => {"AMVCC - Décembre 2023", "amvcc", ~D[2023-12-17]},
      "2023-12-23_wedding.webp" => {"Mariage - Décembre 2023", "wedding", ~D[2023-12-23]},
      "2024-01-27_couples.webp" => {"Couples - Janvier 2024", "couples", ~D[2024-01-27]},
      "2024-03-23_wedding.webp" => {"Mariage - Mars 2024", "wedding", ~D[2024-03-23]},
      "2024-03-24_music.webp" => {"Concert - Mars 2024", "music", ~D[2024-03-24]},
      "2024-03-26_music.webp" => {"Concert - Mars 2024 #2", "music", ~D[2024-03-26]},
      "2024-04-26_amvcc.webp" => {"AMVCC - Avril 2024", "amvcc", ~D[2024-04-26]},
      "2024-05-04_reenactment.webp" => {"Reconstitution - Mai 2024", "reenactment", ~D[2024-05-04]},
      "2024-05-18_wedding.webp" => {"Mariage - Mai 2024", "wedding", ~D[2024-05-18]},
      "2024-07-26_amvcc.webp" => {"AMVCC - Juillet 2024", "amvcc", ~D[2024-07-26]},
      "2024-08-02_reenactment.webp" =>
        {"Reconstitution - Août 2024", "reenactment", ~D[2024-08-02]},
      "2024-08-10_reenactment.webp" =>
        {"Reconstitution - Août 2024 #2", "reenactment", ~D[2024-08-10]},
      "2024-09-08_reenactment.webp" =>
        {"Reconstitution - Septembre 2024", "reenactment", ~D[2024-09-08]},
      "2025-06-14_Minuit_avant_la_Nuit.webp" =>
        {"Minuit avant la Nuit - Aperçu", "reenactment", ~D[2025-06-14]}
    }

    Enum.each(gallery_mapping, fn {filename, {title, category, date}} ->
      slug = filename |> Path.rootname() |> String.downcase() |> String.replace("_", "-")

      album_attrs = %{
        title: title,
        slug: slug,
        type: String.to_atom(category),
        description: "Photo unique du portfolio",
        date_prise_vue: date,
        published: true
      }

      case Photography.create_album(album_attrs) do
        {:ok, album} ->
          Logger.info("Created gallery album: #{album.title}")

          source_file = Path.join([gallery_dir, filename])
          migrate_single_photo(album, source_file, filename)

        {:error, changeset} ->
          Logger.error("Failed to create gallery album #{title}: #{inspect(changeset.errors)}")
      end
    end)
  end

  defp migrate_photos_from_directory(album, source_dir) do
    case File.ls(source_dir) do
      {:ok, files} ->
        photo_files =
          files
          |> Enum.filter(&String.ends_with?(&1, ".webp"))
          |> Enum.sort()

        Logger.info("Found #{length(photo_files)} photos in #{source_dir}")

        photo_files
        |> Enum.with_index(1)
        |> Enum.each(fn {filename, index} ->
          source_path = Path.join([source_dir, filename])
          migrate_single_photo(album, source_path, filename, index)
        end)

      {:error, reason} ->
        Logger.error("Failed to read directory #{source_dir}: #{inspect(reason)}")
    end
  end

  defp migrate_single_photo(album, source_path, original_filename, order \\ 1) do
    # Créer le répertoire de destination
    dest_dir = Path.join(["priv", "static", "uploads", "albums", album.slug, "original"])
    File.mkdir_p!(dest_dir)

    # Calculer le hash du fichier
    file_hash = compute_file_hash(source_path)

    # Générer le nom de fichier final avec hash
    base_name = Path.rootname(original_filename)
    ext = Path.extname(original_filename)
    # Prendre les 8 premiers caractères du hash
    short_hash = String.slice(file_hash, 0, 8)
    final_filename = "#{base_name}-#{short_hash}#{ext}"

    dest_path = Path.join([dest_dir, final_filename])

    # Copier le fichier
    case File.cp(source_path, dest_path) do
      :ok ->
        # Créer l'entrée en base de données
        file_path = "/uploads/albums/#{album.slug}/original/#{final_filename}"

        photo_attrs = %{
          album_id: album.id,
          title: Path.rootname(original_filename),
          file_path: file_path,
          original_filename: original_filename,
          hash: file_hash,
          order: order
        }

        case Repo.insert(Photography.Photo.changeset(%Photography.Photo{}, photo_attrs)) do
          {:ok, photo} ->
            Logger.info("  ✓ Migrated photo: #{original_filename} -> #{photo.file_path}")

          {:error, changeset} ->
            Logger.error(
              "  ✗ Failed to create photo record for #{original_filename}: #{inspect(changeset.errors)}"
            )
        end

      {:error, reason} ->
        Logger.error("  ✗ Failed to copy file #{source_path}: #{inspect(reason)}")
    end
  end

  defp compute_file_hash(file_path) do
    file_path
    |> File.stream!([], 2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
      :crypto.hash_update(acc, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end
