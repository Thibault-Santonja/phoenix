defmodule Portfolio.Photography.ValueObjects.ProcessingStatus do
  @moduledoc """
  Value Object pour le statut de traitement des photos.

  Représente l'état du pipeline de traitement d'une photo (génération des
  variantes, extraction EXIF, etc.).

  ## Invariants

  - Le statut DOIT être l'une des valeurs valides : pending, processing, completed, failed
  - Les transitions sont définies et validées (machine à états)

  ## États

  - `:pending` - En attente de traitement
  - `:processing` - Traitement en cours
  - `:completed` - Traitement terminé avec succès
  - `:failed` - Traitement échoué

  ## Transitions valides

  ```
  pending → processing
  processing → completed
  processing → failed
  failed → pending (retry)
  ```

  ## Pattern DDD

  Un Value Object est :
  - **Immutable :** Ne peut être modifié après création
  - **Auto-validant :** Garantit ses invariants à la création
  - **Égalité par valeur :** Deux statuts identiques sont égaux
  - **Sans identité :** Pas d'ID, comparaison par attributs
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type status :: :pending | :processing | :completed | :failed
  @type t :: %__MODULE__{value: status()}

  @valid_statuses [:pending, :processing, :completed, :failed]

  # Transitions valides: {from, to}
  @valid_transitions [
    {:pending, :processing},
    {:processing, :completed},
    {:processing, :failed},
    {:failed, :pending}
  ]

  @doc """
  Crée un nouveau ProcessingStatus.

  Accepte un atom ou une string représentant le statut.

  ## Exemples

      iex> ProcessingStatus.new(:pending)
      {:ok, %ProcessingStatus{value: :pending}}

      iex> ProcessingStatus.new("completed")
      {:ok, %ProcessingStatus{value: :completed}}

      iex> ProcessingStatus.new(:invalid)
      {:error, :invalid_status}
  """
  @spec new(atom() | String.t()) :: {:ok, t()} | {:error, :invalid_status}
  def new(status) when is_atom(status) do
    if status in @valid_statuses do
      {:ok, %__MODULE__{value: status}}
    else
      {:error, :invalid_status}
    end
  end

  def new(status) when is_binary(status) do
    status
    |> String.to_existing_atom()
    |> new()
  rescue
    ArgumentError -> {:error, :invalid_status}
  end

  @doc """
  Crée un ProcessingStatus en levant une exception en cas d'erreur.

  ## Exemples

      iex> ProcessingStatus.new!(:pending)
      %ProcessingStatus{value: :pending}

      iex> ProcessingStatus.new!(:invalid)
      ** (ArgumentError) Invalid processing status: invalid_status
  """
  @spec new!(atom() | String.t()) :: t()
  def new!(status) do
    case new(status) do
      {:ok, processing_status} -> processing_status
      {:error, reason} -> raise ArgumentError, "Invalid processing status: #{reason}"
    end
  end

  @doc """
  Crée un ProcessingStatus avec la valeur par défaut `:pending`.

  ## Exemples

      iex> ProcessingStatus.default()
      %ProcessingStatus{value: :pending}
  """
  @spec default() :: t()
  def default, do: %__MODULE__{value: :pending}

  @doc """
  Tente une transition vers un nouveau statut.

  Valide que la transition est autorisée par la machine à états.

  ## Exemples

      iex> {:ok, pending} = ProcessingStatus.new(:pending)
      iex> ProcessingStatus.transition(pending, :processing)
      {:ok, %ProcessingStatus{value: :processing}}

      iex> {:ok, pending} = ProcessingStatus.new(:pending)
      iex> ProcessingStatus.transition(pending, :completed)
      {:error, :invalid_transition}
  """
  @spec transition(t(), status()) :: {:ok, t()} | {:error, :invalid_transition}
  def transition(%__MODULE__{value: from}, to) when to in @valid_statuses do
    if {from, to} in @valid_transitions do
      {:ok, %__MODULE__{value: to}}
    else
      {:error, :invalid_transition}
    end
  end

  def transition(%__MODULE__{}, _to), do: {:error, :invalid_transition}

  @doc """
  Vérifie si le statut représente un traitement en cours.

  ## Exemples

      iex> {:ok, status} = ProcessingStatus.new(:pending)
      iex> ProcessingStatus.in_progress?(status)
      true

      iex> {:ok, status} = ProcessingStatus.new(:completed)
      iex> ProcessingStatus.in_progress?(status)
      false
  """
  @spec in_progress?(t()) :: boolean()
  def in_progress?(%__MODULE__{value: value}) when value in [:pending, :processing], do: true
  def in_progress?(%__MODULE__{}), do: false

  @doc """
  Vérifie si le statut représente un traitement terminé (succès ou échec).

  ## Exemples

      iex> {:ok, status} = ProcessingStatus.new(:completed)
      iex> ProcessingStatus.terminal?(status)
      true

      iex> {:ok, status} = ProcessingStatus.new(:failed)
      iex> ProcessingStatus.terminal?(status)
      true

      iex> {:ok, status} = ProcessingStatus.new(:processing)
      iex> ProcessingStatus.terminal?(status)
      false
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{value: value}) when value in [:completed, :failed], do: true
  def terminal?(%__MODULE__{}), do: false

  @doc """
  Vérifie si le traitement a réussi.

  ## Exemples

      iex> {:ok, status} = ProcessingStatus.new(:completed)
      iex> ProcessingStatus.succeeded?(status)
      true
  """
  @spec succeeded?(t()) :: boolean()
  def succeeded?(%__MODULE__{value: :completed}), do: true
  def succeeded?(%__MODULE__{}), do: false

  @doc """
  Vérifie si le traitement a échoué.

  ## Exemples

      iex> {:ok, status} = ProcessingStatus.new(:failed)
      iex> ProcessingStatus.failed?(status)
      true
  """
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{value: :failed}), do: true
  def failed?(%__MODULE__{}), do: false

  @doc """
  Vérifie si le statut peut être retried.

  Seul le statut `failed` peut être retried (transition vers `pending`).

  ## Exemples

      iex> {:ok, status} = ProcessingStatus.new(:failed)
      iex> ProcessingStatus.can_retry?(status)
      true

      iex> {:ok, status} = ProcessingStatus.new(:completed)
      iex> ProcessingStatus.can_retry?(status)
      false
  """
  @spec can_retry?(t()) :: boolean()
  def can_retry?(%__MODULE__{value: :failed}), do: true
  def can_retry?(%__MODULE__{}), do: false

  @doc """
  Extrait la valeur atom du ProcessingStatus.

  ## Exemples

      iex> {:ok, status} = ProcessingStatus.new(:pending)
      iex> ProcessingStatus.to_atom(status)
      :pending
  """
  @spec to_atom(t()) :: status()
  def to_atom(%__MODULE__{value: value}), do: value

  @doc """
  Convertit le ProcessingStatus en string (pour persistence).

  ## Exemples

      iex> {:ok, status} = ProcessingStatus.new(:pending)
      iex> ProcessingStatus.to_string(status)
      "pending"
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{value: value}), do: Atom.to_string(value)

  @doc """
  Vérifie si deux statuts sont égaux (égalité par valeur).

  ## Exemples

      iex> {:ok, s1} = ProcessingStatus.new(:pending)
      iex> {:ok, s2} = ProcessingStatus.new(:pending)
      iex> ProcessingStatus.equal?(s1, s2)
      true
  """
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{value: v1}, %__MODULE__{value: v2}), do: v1 == v2

  @doc """
  Retourne la liste des statuts valides.

  ## Exemples

      iex> ProcessingStatus.valid_statuses()
      [:pending, :processing, :completed, :failed]
  """
  @spec valid_statuses() :: [status()]
  def valid_statuses, do: @valid_statuses

  @doc """
  Retourne la liste des transitions valides.

  ## Exemples

      iex> ProcessingStatus.valid_transitions()
      [{:pending, :processing}, {:processing, :completed}, {:processing, :failed}, {:failed, :pending}]
  """
  @spec valid_transitions() :: [{status(), status()}]
  def valid_transitions, do: @valid_transitions

  # Implémente le protocole String.Chars pour conversion automatique
  defimpl String.Chars do
    def to_string(%{value: value}), do: Atom.to_string(value)
  end
end
