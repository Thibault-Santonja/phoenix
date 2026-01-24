defmodule Portfolio.Photography.Storage do
  @moduledoc """
  Module de configuration pour le backend de stockage des fichiers photo.

  Ce module centralise la logique de sélection du backend de stockage,
  permettant de basculer facilement entre différentes implémentations
  (LocalStorage, S3, etc.) via la configuration.

  ## Configuration

  Le backend de stockage est configuré dans `config/config.exs` :

      config :portfolio, :file_storage,
        backend: Portfolio.Photography.Storage.LocalStorage

  ## Exemples

      iex> Storage.backend()
      Portfolio.Photography.Storage.LocalStorage

      iex> Storage.backend().delete_photo("/path/to/photo.jpg")
      :ok
  """

  @doc """
  Retourne le module du backend de stockage configuré.

  Le backend par défaut est `Portfolio.Photography.Storage.LocalStorage`
  si aucune configuration n'est spécifiée.

  ## Exemples

      iex> backend()
      Portfolio.Photography.Storage.LocalStorage
  """
  @spec backend() :: module()
  def backend do
    Application.get_env(:portfolio, :file_storage)[:backend] ||
      Portfolio.Photography.Storage.LocalStorage
  end
end
