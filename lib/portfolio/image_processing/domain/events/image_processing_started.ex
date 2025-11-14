defmodule Portfolio.ImageProcessing.Domain.Events.ImageProcessingStarted do
  @moduledoc """
  Événement émis lorsque le traitement d'une image démarre.
  """

  @enforce_keys [:image_id, :source_path, :variants, :started_at]
  defstruct [:image_id, :source_path, :variants, :started_at]

  @type t :: %__MODULE__{
          image_id: String.t(),
          source_path: String.t(),
          variants: [atom()],
          started_at: DateTime.t()
        }

  @doc """
  Crée un nouvel événement ImageProcessingStarted.

  ## Exemples

      iex> ImageProcessingStarted.new("abc123", "/tmp/photo.jpg", [:thumbnail, :large], DateTime.utc_now())
      %ImageProcessingStarted{image_id: "abc123", source_path: "/tmp/photo.jpg", variants: [:thumbnail, :large], started_at: ~U[...]}
  """
  @spec new(String.t(), String.t(), [atom()], DateTime.t()) :: t()
  def new(image_id, source_path, variants, started_at) do
    %__MODULE__{
      image_id: image_id,
      source_path: source_path,
      variants: variants,
      started_at: started_at
    }
  end
end
