defmodule LineChat.Chat.Store do
  @moduledoc """
  In-memory chat store, backed by a `GenServer`.

  Users, rooms, messages, read receipts and typing hints all live in one
  process so mutations are serialised and every change can be broadcast on
  `LineChat.PubSub` for LiveView patches.
  """

  use GenServer

  alias LineChat.Chat.{Message, Room, User}

  @pubsub LineChat.PubSub
  @rooms_topic "rooms"
  @typing_ttl_seconds 4

  defstruct users: [],
            rooms: [],
            messages: %{},
            reads: %{},
            typing: %{},
            seq: 0

  @type t :: %__MODULE__{
          users: [User.t()],
          rooms: [Room.t()],
          messages: %{String.t() => [Message.t()]},
          reads: %{String.t() => %{String.t() => DateTime.t()}},
          typing: %{String.t() => %{String.t() => DateTime.t()}},
          seq: non_neg_integer()
        }

  @doc """
  Starts the named store. The application supervises it.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  The PubSub topic carrying room-list changes.
  """
  def rooms_topic, do: @rooms_topic

  @doc """
  The PubSub topic carrying changes for a single room.
  """
  def room_topic(room_id) when is_binary(room_id), do: "rooms:" <> room_id

  @doc """
  Allocates a new id with the given prefix, e.g. `"u-1"`, `"room-2"`.
  """
  def next_id(prefix) when is_binary(prefix) do
    GenServer.call(__MODULE__, {:next_id, prefix})
  end

  @doc """
  Inserts a user. Newest users sort first in `list_users/0`.
  """
  def add_user(%User{} = user) do
    GenServer.call(__MODULE__, {:add_user, user})
  end

  @doc """
  Looks a user up by id.
  """
  def fetch_user(user_id) when is_binary(user_id) do
    GenServer.call(__MODULE__, {:fetch_user, user_id})
  end

  @doc """
  All users, newest first.
  """
  def list_users do
    GenServer.call(__MODULE__, :list_users)
  end

  @doc """
  Inserts a room. Rooms sort oldest first in `list_rooms/0`.
  """
  def add_room(%Room{} = room) do
    GenServer.call(__MODULE__, {:add_room, room})
  end

  @doc """
  Looks a room up by id.
  """
  def fetch_room(room_id) when is_binary(room_id) do
    GenServer.call(__MODULE__, {:fetch_room, room_id})
  end

  @doc """
  All rooms, oldest first.
  """
  def list_rooms do
    GenServer.call(__MODULE__, :list_rooms)
  end

  @doc """
  Renames a room.
  """
  def rename_room(room_id, name) when is_binary(room_id) and is_binary(name) do
    GenServer.call(__MODULE__, {:rename_room, room_id, name})
  end

  @doc """
  Deletes a room together with its messages, reads and typing hints.
  """
  def delete_room(room_id) when is_binary(room_id) do
    GenServer.call(__MODULE__, {:delete_room, room_id})
  end

  @doc """
  Adds a member to a room.
  """
  def add_member(room_id, user_id) when is_binary(room_id) and is_binary(user_id) do
    GenServer.call(__MODULE__, {:add_member, room_id, user_id})
  end

  @doc """
  Removes a member from a room.
  """
  def remove_member(room_id, user_id) when is_binary(room_id) and is_binary(user_id) do
    GenServer.call(__MODULE__, {:remove_member, room_id, user_id})
  end

  @doc """
  Appends a message to its room, oldest-first ordering preserved.
  """
  def append_message(%Message{} = message) do
    GenServer.call(__MODULE__, {:append_message, message})
  end

  @doc """
  Messages of a room, oldest first.
  """
  def list_messages(room_id) when is_binary(room_id) do
    GenServer.call(__MODULE__, {:list_messages, room_id})
  end

  @doc """
  Finds a message across every room.
  """
  def find_message(message_id) when is_binary(message_id) do
    GenServer.call(__MODULE__, {:find_message, message_id})
  end

  @doc """
  Marks a message as redacted.
  """
  def redact_message(message_id) when is_binary(message_id) do
    GenServer.call(__MODULE__, {:redact_message, message_id})
  end

  @doc """
  Records that `user_id` has read everything in `room_id` as of `at`.
  """
  def mark_read(room_id, user_id, at \\ DateTime.utc_now()) do
    GenServer.call(__MODULE__, {:mark_read, room_id, user_id, at})
  end

  @doc """
  The newest read receipt for a user in a room, or `nil`.
  """
  def last_read(room_id, user_id) do
    GenServer.call(__MODULE__, {:last_read, room_id, user_id})
  end

  @doc """
  Every read receipt in a room, keyed by user id.
  """
  def reads_for(room_id) when is_binary(room_id) do
    GenServer.call(__MODULE__, {:reads_for, room_id})
  end

  @doc """
  Publishes that `user_id` is typing in `room_id` until the ttl expires.
  """
  def set_typing(room_id, user_id, ttl_seconds \\ @typing_ttl_seconds) do
    GenServer.call(__MODULE__, {:set_typing, room_id, user_id, ttl_seconds})
  end

  @doc """
  User ids currently typing in a room, sorted, expiring against `now`.
  """
  def typing_users(room_id, now \\ DateTime.utc_now()) do
    GenServer.call(__MODULE__, {:typing_users, room_id, now})
  end

  @doc """
  Clears everything, keeping the id counter monotonic.
  """
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:next_id, prefix}, _from, state) do
    seq = state.seq + 1
    {:reply, prefix <> "-" <> Integer.to_string(seq), %{state | seq: seq}}
  end

  def handle_call({:add_user, user}, _from, state) do
    state = %{state | users: [user | state.users]}
    broadcast(@rooms_topic, {:line_chat, :user_added, user})
    {:reply, {:ok, user}, state}
  end

  def handle_call({:fetch_user, user_id}, _from, state) do
    {:reply, state.users |> Enum.find(&(&1.id == user_id)) |> wrap(), state}
  end

  def handle_call(:list_users, _from, state), do: {:reply, state.users, state}

  def handle_call({:add_room, room}, _from, state) do
    state = %{state | rooms: state.rooms ++ [room]}
    broadcast(@rooms_topic, {:line_chat, :rooms_changed})
    {:reply, {:ok, room}, state}
  end

  def handle_call({:fetch_room, room_id}, _from, state) do
    {:reply, state.rooms |> Enum.find(&(&1.id == room_id)) |> wrap(), state}
  end

  def handle_call(:list_rooms, _from, state), do: {:reply, state.rooms, state}

  def handle_call({:rename_room, room_id, name}, _from, state) do
    case find_room(state, room_id) do
      nil -> {:reply, {:error, :room_not_found}, state}
      room -> respond_room(%{room | name: name}, state)
    end
  end

  def handle_call({:delete_room, room_id}, _from, state) do
    case find_room(state, room_id) do
      nil ->
        {:reply, {:error, :room_not_found}, state}

      _room ->
        state = %{
          state
          | rooms: Enum.reject(state.rooms, &(&1.id == room_id)),
            messages: Map.delete(state.messages, room_id),
            reads: Map.delete(state.reads, room_id),
            typing: Map.delete(state.typing, room_id)
        }

        broadcast(@rooms_topic, {:line_chat, :rooms_changed})
        broadcast(room_topic(room_id), {:line_chat, :room_deleted, room_id})
        {:reply, {:ok, room_id}, state}
    end
  end

  def handle_call({:add_member, room_id, user_id}, _from, state) do
    case find_room(state, room_id) do
      nil -> {:reply, {:error, :room_not_found}, state}
      room -> respond_room(Room.add_member(room, user_id), state)
    end
  end

  def handle_call({:remove_member, room_id, user_id}, _from, state) do
    case find_room(state, room_id) do
      nil -> {:reply, {:error, :room_not_found}, state}
      room -> respond_room(Room.remove_member(room, user_id), state)
    end
  end

  def handle_call({:append_message, message}, _from, state) do
    room_id = message.room_id
    messages = Map.get(state.messages, room_id, [])
    state = %{state | messages: Map.put(state.messages, room_id, messages ++ [message])}
    broadcast(room_topic(room_id), {:line_chat, :message_created, message})
    broadcast(@rooms_topic, {:line_chat, :rooms_changed})
    {:reply, {:ok, message}, state}
  end

  def handle_call({:list_messages, room_id}, _from, state) do
    {:reply, Map.get(state.messages, room_id, []), state}
  end

  def handle_call({:find_message, message_id}, _from, state) do
    message =
      state.messages
      |> Map.values()
      |> List.flatten()
      |> Enum.find(&(&1.id == message_id))

    {:reply, wrap(message), state}
  end

  def handle_call({:redact_message, message_id}, _from, state) do
    message =
      state.messages
      |> Map.values()
      |> List.flatten()
      |> Enum.find(&(&1.id == message_id))

    case wrap(message) do
      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}

      {:ok, message} ->
        redacted = Message.redact(message)
        messages = replace_message(state.messages, message, redacted)
        broadcast(room_topic(message.room_id), {:line_chat, :message_redacted, redacted})
        {:reply, {:ok, redacted}, %{state | messages: messages}}
    end
  end

  def handle_call({:mark_read, room_id, user_id, at}, _from, state) do
    room_reads = Map.get(state.reads, room_id, %{})
    reads = Map.put(state.reads, room_id, Map.put(room_reads, user_id, at))
    broadcast(room_topic(room_id), {:line_chat, :read_marked, room_id})
    {:reply, {:ok, at}, %{state | reads: reads}}
  end

  def handle_call({:last_read, room_id, user_id}, _from, state) do
    {:reply, get_in(state.reads, [room_id, user_id]), state}
  end

  def handle_call({:reads_for, room_id}, _from, state) do
    {:reply, Map.get(state.reads, room_id, %{}), state}
  end

  def handle_call({:set_typing, room_id, user_id, ttl}, _from, state) do
    until = DateTime.add(DateTime.utc_now(), ttl, :second)
    room_typing = Map.get(state.typing, room_id, %{})
    typing = Map.put(state.typing, room_id, Map.put(room_typing, user_id, until))
    broadcast(room_topic(room_id), {:line_chat, :typing_changed, room_id})
    {:reply, {:ok, until}, %{state | typing: typing}}
  end

  def handle_call({:typing_users, room_id, now}, _from, state) do
    ids =
      state.typing
      |> Map.get(room_id, %{})
      |> Enum.filter(fn {_user_id, until} -> DateTime.compare(until, now) == :gt end)
      |> Enum.map(fn {user_id, _until} -> user_id end)
      |> Enum.sort()

    {:reply, ids, state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | users: [], rooms: [], messages: %{}, reads: %{}, typing: %{}}}
  end

  defp find_room(state, room_id) do
    Enum.find(state.rooms, &(&1.id == room_id))
  end

  defp respond_room(room, state) do
    rooms =
      Enum.map(state.rooms, fn current ->
        if current.id == room.id, do: room, else: current
      end)

    broadcast(@rooms_topic, {:line_chat, :rooms_changed})
    broadcast(room_topic(room.id), {:line_chat, :room_updated, room})
    {:reply, {:ok, room}, %{state | rooms: rooms}}
  end

  defp replace_message(messages, old, new) do
    Map.new(messages, fn {room_id, room_messages} ->
      {room_id, Enum.map(room_messages, fn m -> if m.id == old.id, do: new, else: m end)}
    end)
  end

  defp wrap(nil), do: {:error, :not_found}
  defp wrap(value), do: {:ok, value}

  defp broadcast(topic, payload) do
    Phoenix.PubSub.broadcast(@pubsub, topic, payload)
  end
end
