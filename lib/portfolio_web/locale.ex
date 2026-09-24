defmodule PortfolioWeb.Locale do
  @moduledoc """
  Les langues que le portfolio parle, et la lecture du paramètre `hl`.

  `hl` est le paramètre de langue de Google : il arrive par l'adresse, donc
  un lien partagé, un robot ou un visiteur peuvent y mettre n'importe quoi,
  de `fr-FR` à une chaîne de mille caractères. Il n'est retenu que s'il
  désigne une langue effectivement servie.

  La validation n'est pas cosmétique. Une locale inconnue relayée à la
  plateforme photo vaut un 400, donc une page « momentanément indisponible »
  à la place de l'album ; et comme la locale entre dans la clé de cache du
  catalogue, chaque valeur distincte est un défaut de cache de plus, qui
  évince des entrées légitimes du plafond de cent.
  """

  @supported Gettext.known_locales(PortfolioWeb.Gettext)

  @doc """
  Les codes de langue servis par le portfolio.
  """
  @spec supported() :: [String.t()]
  def supported, do: @supported

  @doc """
  Langue demandée par le paramètre `hl`, ou `defaut` quand elle n'est pas
  servie.
  """
  @spec from_params(map(), String.t()) :: String.t()
  def from_params(params, defaut) when is_map(params) and is_binary(defaut) do
    case Map.get(params, "hl") do
      langue when langue in @supported -> langue
      _autre -> defaut
    end
  end
end
