defmodule Portfolio.ImageProcessing.Domain.Events.ImageProcessingCompleted do
  @moduledoc """
  Événement émis lorsque le traitement d'une image est terminé avec succès.
  """

  @enforce_keys [:image_id, :variants_generated, :duration_ms, :completed_at]
  defstruct [:image_id, :variants_generated, :duration_ms, :completed_at]

  @type t :: %__MODULE__{
          image_id: String.t(),
          variants_generated: %{atom() => String.t()},
          duration_ms: non_neg_integer(),
          completed_at: DateTime.t()
        }

  @doc """
  Crée un nouvel événement ImageProcessingCompleted.

  ## Exemples

      iex> variants = %{thumbnail: "/path/thumb.webp", large: "/path/large.webp"}
      iex> ImageProcessingCompleted.new("abc123", variants, 5000, DateTime.utc_now())
      %ImageProcessingCompleted{image_id: "abc123", variants_generated: %{...}, duration_ms: 5000, ...}
  """
  @spec new(String.t(), map(), non_neg_integer(), DateTime.t()) :: t()
  def new(image_id, variants_generated, duration_ms, completed_at) do
    %__MODULE__{
      image_id: image_id,
      variants_generated: variants_generated,
      duration_ms: duration_ms,
      completed_at: completed_at
    }
  end
end
