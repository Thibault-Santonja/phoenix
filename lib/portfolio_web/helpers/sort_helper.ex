defmodule PortfolioWeb.Helpers.SortHelper do
  @moduledoc """
  Helper centralisé pour la logique de tri dans les LiveViews admin.

  Fournit un cycle de tri à 3 états :
  - Pour les dates : desc -> asc -> none
  - Pour les autres colonnes : asc -> desc -> none

  ## Utilisation

      # Dans un LiveView
      alias PortfolioWeb.Helpers.SortHelper

      # Déterminer le prochain état de tri
      {next_sort_by, next_sort_order} = SortHelper.next_sort_state("title", current_sort_by, current_sort_order)

      # Obtenir l'icône de tri
      icon = SortHelper.sort_icon("title", current_sort_by, current_sort_order)

      # Construire la clause ORDER BY pour Ecto
      order_by = SortHelper.build_order_by("title", "asc", column_mapping())

  ## Configuration des colonnes

  Les colonnes sont mappées via une fonction de configuration qui retourne
  le nom du champ Ecto correspondant :

      def column_mapping do
        %{
          "title" => :title,
          "date" => :date_prise_vue,
          "photos" => :photo_count
        }
      end
  """

  @type sort_direction :: String.t() | nil
  @type column :: String.t()
  @type sort_state :: {column() | nil, sort_direction()}

  @doc """
  Détermine le prochain état de tri pour une colonne.

  Implémente un cycle à 3 états :
  - Pour les colonnes de date : desc -> asc -> none
  - Pour les autres colonnes : asc -> desc -> none

  ## Paramètres

  - `column` - La colonne sur laquelle on clique
  - `current_sort_by` - La colonne actuellement triée (nil si aucune)
  - `current_sort_order` - L'ordre actuel ("asc", "desc", ou nil)

  ## Exemples

      iex> SortHelper.next_sort_state("title", nil, nil)
      {"title", "asc"}

      iex> SortHelper.next_sort_state("title", "title", "asc")
      {"title", "desc"}

      iex> SortHelper.next_sort_state("title", "title", "desc")
      {nil, nil}

      iex> SortHelper.next_sort_state("date", nil, nil)
      {"date", "desc"}
  """
  @spec next_sort_state(column(), column() | nil, sort_direction()) :: sort_state()
  def next_sort_state(column, current_sort_by, current_sort_order) do
    cond do
      current_sort_by != column or current_sort_by == nil ->
        initial_sort_order(column)

      current_sort_by == column ->
        cycle_sort_order(column, current_sort_order)
    end
  end

  @doc """
  Retourne l'ordre de tri initial pour une colonne.

  Les colonnes de date commencent par "desc" (plus récent en premier).
  Les autres colonnes commencent par "asc" (ordre alphabétique).

  ## Exemples

      iex> SortHelper.initial_sort_order("date")
      {"date", "desc"}

      iex> SortHelper.initial_sort_order("title")
      {"title", "asc"}
  """
  @spec initial_sort_order(column()) :: sort_state()
  def initial_sort_order("date"), do: {"date", "desc"}
  def initial_sort_order(column), do: {column, "asc"}

  @doc """
  Passe à l'état suivant dans le cycle de tri.

  ## Exemples

      iex> SortHelper.cycle_sort_order("date", "desc")
      {"date", "asc"}

      iex> SortHelper.cycle_sort_order("date", "asc")
      {nil, nil}

      iex> SortHelper.cycle_sort_order("title", "asc")
      {"title", "desc"}

      iex> SortHelper.cycle_sort_order("title", "desc")
      {nil, nil}
  """
  @spec cycle_sort_order(column(), sort_direction()) :: sort_state()
  def cycle_sort_order("date", "desc"), do: {"date", "asc"}
  def cycle_sort_order("date", "asc"), do: {nil, nil}
  def cycle_sort_order(column, "asc"), do: {column, "desc"}
  def cycle_sort_order(_column, "desc"), do: {nil, nil}
  def cycle_sort_order(_column, _), do: {nil, nil}

  @doc """
  Retourne l'icône de tri pour une colonne.

  ## Exemples

      iex> SortHelper.sort_icon("title", "title", "asc")
      "↑"

      iex> SortHelper.sort_icon("title", "title", "desc")
      "↓"

      iex> SortHelper.sort_icon("title", "date", "asc")
      ""

      iex> SortHelper.sort_icon("title", nil, nil)
      ""
  """
  @spec sort_icon(column(), column() | nil, sort_direction()) :: String.t()
  def sort_icon(column, current_sort_by, current_sort_order) do
    cond do
      current_sort_by == column and current_sort_order == "asc" -> "↑"
      current_sort_by == column and current_sort_order == "desc" -> "↓"
      true -> ""
    end
  end

  @doc """
  Construit la clause ORDER BY pour Ecto.

  Utilise un mapping de colonnes pour convertir les noms de colonnes UI
  vers les noms de champs Ecto.

  ## Paramètres

  - `sort_by` - Le nom de la colonne à trier (ou nil)
  - `sort_order` - L'ordre de tri ("asc" ou "desc")
  - `column_mapping` - Map des colonnes UI vers les champs Ecto
  - `default_order` - Ordre par défaut si aucun tri spécifié (optionnel)

  ## Exemples

      iex> mapping = %{"title" => :title, "date" => :date_prise_vue}
      iex> SortHelper.build_order_by("title", "asc", mapping)
      [asc: :title]

      iex> mapping = %{"title" => :title, "date" => :date_prise_vue}
      iex> SortHelper.build_order_by("date", "desc", mapping)
      [desc: :date_prise_vue]

      iex> mapping = %{"title" => :title}
      iex> SortHelper.build_order_by(nil, nil, mapping, [desc: :inserted_at])
      [desc: :inserted_at]
  """
  @spec build_order_by(
          column() | nil,
          sort_direction(),
          %{column() => atom()},
          keyword()
        ) :: keyword()
  def build_order_by(sort_by, sort_order, column_mapping, default_order \\ [])

  def build_order_by(nil, _, _column_mapping, default_order), do: default_order
  def build_order_by(_, nil, _column_mapping, default_order), do: default_order

  def build_order_by(sort_by, sort_order, column_mapping, default_order) do
    case Map.get(column_mapping, sort_by) do
      nil ->
        default_order

      field when sort_order == "asc" ->
        [asc: field]

      field when sort_order == "desc" ->
        [desc: field]

      _ ->
        default_order
    end
  end
end
