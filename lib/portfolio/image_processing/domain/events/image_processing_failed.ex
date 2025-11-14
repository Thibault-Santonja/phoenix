defmodule Portfolio.ImageProcessing.Domain.Events.ImageProcessingFailed do
  @moduledoc """
  Événement émis lorsque le traitement d'une image échoue.
  """

  @enforce_keys [:image_id, :reason, :failed_at]
  defstruct [:image_id, :reason, :failed_at, :variant_name]

  @type failure_reason ::
          :file_not_found
          | :corrupted_file
          | :disk_full
          | :processing_error
          | {:variant_failed, atom(), term()}

  @type t :: %__MODULE__{
          image_id: String.t(),
          reason: failure_reason(),
          failed_at: DateTime.t(),
          variant_name: atom() | nil
        }

  @doc """
  Crée un nouvel événement ImageProcessingFailed.

  ## Exemples

      iex> ImageProcessingFailed.new("abc123", :file_not_found, DateTime.utc_now())
      %ImageProcessingFailed{image_id: "abc123", reason: :file_not_found, failed_at: ~U[...]}

      iex> ImageProcessingFailed.new("abc123", {:variant_failed, :thumbnail, :resize_error}, DateTime.utc_now(), :thumbnail)
      %ImageProcessingFailed{image_id: "abc123", reason: {:variant_failed, :thumbnail, :resize_error}, ...}
  """
  @spec new(String.t(), failure_reason(), DateTime.t(), atom() | nil) :: t()
  def new(image_id, reason, failed_at, variant_name \\ nil) do
    %__MODULE__{
      image_id: image_id,
      reason: reason,
      failed_at: failed_at,
      variant_name: variant_name
    }
  end
end
