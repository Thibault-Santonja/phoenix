defmodule PortfolioWeb.Helpers.AlbumTypeFormatter do
  @moduledoc """
  Helper module for formatting album type labels.

  Centralizes the translation logic for album types to avoid duplication
  across LiveView components.
  """

  use Gettext, backend: PortfolioWeb.Gettext

  @doc """
  Formats an album type atom to a localized string.

  ## Examples

      iex> format_type(:wedding)
      "Mariage"  # or translated value

      iex> format_type(:amvcc)
      "AMVCC"
  """
  @spec format_type(atom()) :: String.t()
  def format_type(:couples), do: gettext("album.type.couples")
  def format_type(:wedding), do: gettext("album.type.wedding")
  def format_type(:motherhood), do: gettext("album.type.motherhood")
  def format_type(:events), do: gettext("album.type.events")
  def format_type(:landscape), do: gettext("album.type.landscape")
  def format_type(:street), do: gettext("album.type.street")
  def format_type(:music), do: gettext("album.type.music")
  def format_type(:reenactment), do: gettext("album.type.reenactment")
  def format_type(:amvcc), do: "AMVCC"
  def format_type(:china), do: gettext("album.type.china")
  def format_type(:japan), do: gettext("album.type.japan")
  def format_type(:taiwan), do: gettext("album.type.taiwan")
  def format_type(type) when is_atom(type), do: to_string(type)
  def format_type(type) when is_binary(type), do: format_type(String.to_existing_atom(type))

  @doc """
  Formats a chapter string to a localized title.

  Some chapters have special formatting (e.g., "motherhood" uses a different
  gettext key for historical reasons).

  ## Examples

      iex> format_chapter_title("wedding")
      "Mariage"

      iex> format_chapter_title("amvcc")
      "AMVCC"
  """
  @spec format_chapter_title(String.t()) :: String.t()
  def format_chapter_title("amvcc"), do: "AMVCC"
  def format_chapter_title("china"), do: gettext("album.type.china")
  def format_chapter_title("couples"), do: gettext("album.type.couples")
  def format_chapter_title("events"), do: gettext("album.type.events")
  def format_chapter_title("japan"), do: gettext("album.type.japan")
  def format_chapter_title("landscape"), do: gettext("album.type.landscape")
  def format_chapter_title("motherhood"), do: gettext("photography.motherhood_families")
  def format_chapter_title("music"), do: gettext("photography.concerts_music")
  def format_chapter_title("reenactment"), do: gettext("album.type.reenactment")
  def format_chapter_title("street"), do: gettext("photography.street_photography")
  def format_chapter_title("taiwan"), do: gettext("album.type.taiwan")
  def format_chapter_title("wedding"), do: gettext("album.type.wedding")
  def format_chapter_title(_), do: gettext("photography.gallery")
end
