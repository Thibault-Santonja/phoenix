defmodule Portfolio.Auth.IPWhitelist do
  @moduledoc """
  Schema for whitelisted IP addresses that are not subject to rate limiting.

  Whitelisted IPs are typically trusted addresses such as:
  - Administrator's office
  - Monitoring servers
  - Internal IPs
  - Trusted partners

  ## Fields

  - `ip_address` - IP address (IPv4 or IPv6)
  - `description` - Optional description of the IP
  - `created_by_id` - ID of the user who added the IP
  - `inserted_at` - Date when added to the whitelist

  ## Examples

      # IPv4
      %IPWhitelist{
        ip_address: "192.168.1.100",
        description: "Office main router",
        created_by_id: admin_id
      }

      # IPv6
      %IPWhitelist{
        ip_address: "2001:db8::1",
        description: "Monitoring server",
        created_by_id: admin_id
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolio.Auth.User

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          ip_address: String.t(),
          description: String.t() | nil,
          created_by_id: Ecto.UUID.t() | nil,
          created_by: User.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ip_whitelist" do
    field :ip_address, :string
    field :description, :string

    belongs_to :created_by, User, foreign_key: :created_by_id

    timestamps(updated_at: false)
  end

  @doc """
  Creates a changeset for a whitelist entry.

  ## Validations

  - `ip_address` is required and must be a valid IP address (IPv4 or IPv6)
  - `ip_address` must be unique
  - `description` is optional (max 500 characters)

  ## Examples

      iex> changeset(%IPWhitelist{}, %{
      ...>   ip_address: "192.168.1.100",
      ...>   description: "Office IP",
      ...>   created_by_id: admin_id
      ...> })
      %Ecto.Changeset{valid?: true}

      iex> changeset(%IPWhitelist{}, %{ip_address: "invalid"})
      %Ecto.Changeset{valid?: false}
  """
  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(ip_whitelist, attrs) do
    ip_whitelist
    |> cast(attrs, [:ip_address, :description, :created_by_id])
    |> validate_required([:ip_address])
    |> normalize_ip_address()
    |> validate_ip_format()
    |> validate_length(:description, max: 500)
    |> unique_constraint(:ip_address)
  end

  @doc """
  Changeset for updating (does not allow changing the IP).
  """
  @spec update_changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def update_changeset(ip_whitelist, attrs) do
    ip_whitelist
    |> cast(attrs, [:description])
    |> validate_length(:description, max: 500)
  end

  # Normalizes the IP address (trim whitespace)
  defp normalize_ip_address(changeset) do
    case get_change(changeset, :ip_address) do
      nil ->
        changeset

      ip ->
        put_change(changeset, :ip_address, String.trim(ip))
    end
  end

  # Validates the IP address format (IPv4 or IPv6)
  defp validate_ip_format(changeset) do
    validate_change(changeset, :ip_address, fn :ip_address, ip ->
      case parse_ip(ip) do
        {:ok, _parsed} -> []
        :error -> [ip_address: "has invalid format"]
      end
    end)
  end

  # Parses an IP address (IPv4 or IPv6)
  @spec parse_ip(String.t()) :: {:ok, :inet.ip_address()} | :error
  defp parse_ip(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, :einval} -> :error
    end
  end
end
