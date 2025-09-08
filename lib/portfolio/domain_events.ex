defmodule Portfolio.DomainEvents do
  @moduledoc """
  Domain Events system for decoupling bounded contexts.

  Uses Phoenix.PubSub for event broadcasting between contexts.
  Implements the Domain Events pattern from Domain-Driven Design.

  ## Overview

  Domain Events allow bounded contexts to communicate in a loosely coupled way.
  When something important happens in one context (e.g., an album is published),
  other contexts can react without creating tight coupling.

  ## Event Flow

  1. A domain action occurs (e.g., `Photography.publish_album/1`)
  2. The context publishes a domain event via `DomainEvents.publish/2`
  3. Subscribed handlers receive the event and react accordingly
  4. Each handler processes the event independently

  ## Benefits

  - **Decoupling**: Contexts don't need to know about each other
  - **Extensibility**: Add new handlers without modifying publishers
  - **Audit Trail**: All domain events are broadcast and can be logged
  - **Scalability**: Asynchronous processing via PubSub

  ## Usage

  ### Publishing Events

      # In a context module
      alias Portfolio.DomainEvents
      alias Portfolio.Photography.Events.AlbumPublished

      def publish_album(%Album{} = album) do
        # ... business logic ...

        DomainEvents.publish(:album_published, %AlbumPublished{
          album_id: album.id,
          title: album.title,
          slug: album.slug,
          published_at: DateTime.utc_now()
        })

        {:ok, album}
      end

  ### Subscribing to Events

      # In an event handler GenServer
      def init(_) do
        DomainEvents.subscribe(:album_published)
        {:ok, %{}}
      end

      def handle_info({:album_published, event}, state) do
        # React to event
        Logger.info("Album published: \#{event.title}")
        {:noreply, state}
      end

  ## Event Naming Convention

  - Use past tense: `:album_published`, not `:publish_album`
  - Be specific: `:photo_uploaded`, not `:photo_changed`
  - Use domain language: `:magic_link_requested`, not `:email_sent`
  """

  alias Phoenix.PubSub

  @pubsub Portfolio.PubSub

  @doc """
  Publishes a domain event to all subscribers.

  Events are broadcast asynchronously via Phoenix.PubSub.

  ## Parameters

    - `event_type` - Atom identifying the event type (e.g., `:album_published`)
    - `payload` - Event data structure (typically a struct with event details)

  ## Examples

      iex> DomainEvents.publish(:album_published, %AlbumPublished{album_id: "123"})
      :ok

      iex> DomainEvents.publish(:photo_uploaded, %PhotoUploaded{photo_id: "456"})
      :ok
  """
  @spec publish(atom(), term()) :: :ok
  def publish(event_type, payload) when is_atom(event_type) do
    PubSub.broadcast(@pubsub, topic(event_type), {event_type, payload})
  end

  @doc """
  Subscribes the current process to a domain event type.

  After subscribing, the process will receive messages of the form:
  `{event_type, payload}` when events of that type are published.

  ## Parameters

    - `event_type` - Atom identifying the event type to subscribe to

  ## Examples

      iex> DomainEvents.subscribe(:album_published)
      :ok

      # Process will now receive messages like:
      # {:album_published, %AlbumPublished{...}}
  """
  @spec subscribe(atom()) :: :ok | {:error, term()}
  def subscribe(event_type) when is_atom(event_type) do
    PubSub.subscribe(@pubsub, topic(event_type))
  end

  @doc """
  Unsubscribes the current process from a domain event type.

  ## Parameters

    - `event_type` - Atom identifying the event type to unsubscribe from

  ## Examples

      iex> DomainEvents.unsubscribe(:album_published)
      :ok
  """
  @spec unsubscribe(atom()) :: :ok
  def unsubscribe(event_type) when is_atom(event_type) do
    PubSub.unsubscribe(@pubsub, topic(event_type))
  end

  # Generates a unique topic name for each event type
  @spec topic(atom()) :: String.t()
  defp topic(event_type), do: "domain_events:#{event_type}"
end
