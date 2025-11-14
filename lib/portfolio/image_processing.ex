defmodule Portfolio.ImageProcessing do
  @moduledoc """
  Bounded Context pour le traitement d'images.

  Ce contexte encapsule toute la logique liée au traitement d'images :
  - Génération de variants optimisés (WebP, AVIF)
  - Redimensionnement intelligent préservant l'aspect ratio
  - Compression avec qualité configurable
  - Émission d'événements domaine

  ## Architecture

  Le contexte suit les principes DDD :
  - **Domain Layer**: Entities, Value Objects, Domain Events
  - **Application Layer**: Services orchestrant la logique métier
  - **Infrastructure Layer**: Adapters pour libvips (Vix)

  ## Configuration

  Les variants sont configurés via l'application config :

      config :portfolio, :image_variants,
        thumbnail: [width: 400, quality: 75, format: :webp, effort: 4],
        small: [width: 768, quality: 80, format: :webp, effort: 4],
        medium: [width: 1280, quality: 85, format: :webp, effort: 4],
        large: [width: 1920, quality: 90, format: :avif, effort: 6]

  ## Usage

      # Générer tous les variants d'une image
      ImageProcessing.generate_variants("photo_id", "/tmp/photo.jpg", "/uploads/photo_id")
      #=> {:ok, %{thumbnail: "/uploads/photo_id/thumbnail.webp", ...}}

      # Récupérer la configuration des variants
      ImageProcessing.variants()
      #=> %{thumbnail: %{width: 400, quality: 75, ...}, ...}

  ## Événements Domaine

  Le contexte émet les événements suivants :
  - `:image_processing_started` - Début du traitement
  - `:image_processing_completed` - Traitement réussi
  - `:image_processing_failed` - Échec du traitement
  """

  alias Portfolio.ImageConfig
  alias Portfolio.ImageProcessing.Services.ImageProcessingService

  @type variant :: :thumbnail | :small | :medium | :large
  @type variant_config :: %{
          width: pos_integer(),
          quality: pos_integer(),
          format: :webp | :avif | :jpeg,
          effort: pos_integer()
        }
  @type variants_map :: %{variant() => String.t()}

  # =============================================================================
  # Public API - Image Processing
  # =============================================================================

  @doc """
  Génère tous les variants configurés d'une image.

  ## Paramètres

    * `image_id` - Identifiant unique de l'image
    * `source_path` - Chemin vers le fichier image source
    * `output_base_path` - Répertoire de sortie pour les variants

  ## Retour

    * `{:ok, variants_map}` - Map des variants générés (nom => chemin de fichier)
    * `{:error, reason}` - Raison de l'échec

  ## Exemples

      iex> ImageProcessing.generate_variants("abc123", "/tmp/photo.jpg", "/uploads/photos/abc123")
      {:ok, %{
        thumbnail: "/uploads/photos/abc123/thumbnail.webp",
        small: "/uploads/photos/abc123/small.webp",
        medium: "/uploads/photos/abc123/medium.webp",
        large: "/uploads/photos/abc123/large.avif"
      }}

      iex> ImageProcessing.generate_variants("abc123", "/invalid.jpg", "/uploads/abc123")
      {:error, :file_not_found}

  ## Erreurs Possibles

    * `:file_not_found` - Le fichier source n'existe pas
    * `:corrupted_file` - Le fichier est corrompu ou dans un format invalide
    * `:disk_full` - Espace disque insuffisant
    * `{:variant_failed, variant_name, reason}` - Échec de génération d'un variant
  """
  @spec generate_variants(String.t(), String.t(), String.t()) ::
          {:ok, variants_map()} | {:error, term()}
  def generate_variants(image_id, source_path, output_base_path) do
    ImageProcessingService.generate_variants(image_id, source_path, output_base_path)
  end

  # =============================================================================
  # Public API - Configuration
  # =============================================================================

  @doc """
  Retourne la configuration de tous les variants.

  Délègue à ImageConfig pour la centralisation de la configuration.

  ## Exemples

      iex> ImageProcessing.variants()
      %{
        thumbnail: %{width: 400, quality: 75, format: :webp, effort: 4},
        small: %{width: 768, quality: 80, format: :webp, effort: 4},
        medium: %{width: 1280, quality: 85, format: :webp, effort: 4},
        large: %{width: 1920, quality: 90, format: :avif, effort: 6}
      }
  """
  @spec variants() :: %{variant() => variant_config()}
  def variants do
    ImageConfig.variants()
  end

  @doc """
  Retourne la configuration d'un variant spécifique.

  ## Exemples

      iex> ImageProcessing.variant(:thumbnail)
      %{width: 400, quality: 75, format: :webp, effort: 4}

      iex> ImageProcessing.variant(:nonexistent)
      nil
  """
  @spec variant(variant()) :: variant_config() | nil
  def variant(name) do
    ImageConfig.variant(name)
  end

  @doc """
  Retourne l'extension de fichier pour un format donné.

  ## Exemples

      iex> ImageProcessing.file_extension(:webp)
      "webp"

      iex> ImageProcessing.file_extension(:avif)
      "avif"

      iex> ImageProcessing.file_extension(:jpeg)
      "jpg"
  """
  @spec file_extension(:webp | :avif | :jpeg) :: String.t()
  def file_extension(:webp), do: "webp"
  def file_extension(:avif), do: "avif"
  def file_extension(:jpeg), do: "jpg"
end
