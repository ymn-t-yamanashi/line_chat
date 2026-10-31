defmodule LineChat.Chat do
  @moduledoc """
  Facade over `LineChat.Chat.Store`.

  Everything the web layer needs: guest identities, rooms, messages, read
  receipts, typing hints and PubSub subscriptions. Errors are domain-specific
  (`:room_not_found`, `:not_a_member`, `:too_long`, …) so the UI can label them.
  """

  alias LineChat.Chat.{Message, Room, RoomSummary, Store, Time, User}

  @pubsub LineChat.PubSub
  @room_name_limit 50
  @typing_ttl_seconds 4
  @default_guest_name "ゲスト"
  @default_color "#06c755"
  @palette ["#06c755", "#67b9e8", "#f5b942", "#e77fb2", "#9a8ad6", "#59c1c0"]

  @doc """
  Creates a guest identity for a browser session and joins every room.

  When `name` is omitted the guest is named after its own id, which keeps
  simultaneous guests distinguishable in the transcript.
  """
  def create_guest_user(name \\ nil) do
    id = Store.next_id("u")
    user = User.new(id, guest_name(id, name), color_for(id))
    {:ok, user} = Store.add_user(user)
    join_all_rooms(user.id)
    {:ok, user}
  end

  @doc """
  Adds a named user, optionally overriding the avatar colour.
  """
  def add_user(name, color \\ nil)

  def add_user(name, color) when is_binary(name) do
    case validate_room_name(name) do
      {:ok, trimmed} ->
        Store.add_user(User.new(Store.next_id("u"), trimmed, color_for_user(color)))

      {:error, reason} ->
        {:error, reason}
    end
  end

  def add_user(_name, _color), do: {:error, :invalid_name}

  @doc """
  Fetches a user by id.
  """
  def fetch_user(user_id) when is_binary(user_id) do
    translate(Store.fetch_user(user_id), :user_not_found)
  end

  def fetch_user(_user_id), do: {:error, :user_not_found}

  @doc """
  All users, newest first.
  """
  def list_users, do: Store.list_users()

  @doc """
  Creates a room. A blank or over-long name is rejected.
  """
  def create_room(name, member_ids \\ [])

  def create_room(name, member_ids) do
    with {:ok, trimmed} <- validate_room_name(name),
         true <- member_ids != [] do
      room =
        Room.new(Store.next_id("room"), trimmed, member_ids, DateTime.utc_now())

      {:ok, room} = Store.add_room(room)
      {:ok, room}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_members}
    end
  end

  @doc """
  Fetches a room by id.
  """
  def fetch_room(room_id) when is_binary(room_id) do
    translate(Store.fetch_room(room_id), :room_not_found)
  end

  def fetch_room(_room_id), do: {:error, :room_not_found}

  @doc """
  Rooms the viewer belongs to, newest activity first.
  """
  def list_rooms(viewer_id) when is_binary(viewer_id) do
    now = DateTime.utc_now()

    Store.list_rooms()
    |> Enum.filter(&Room.member?(&1, viewer_id))
    |> Enum.map(fn room -> summary(room, viewer_id, now) end)
    |> Enum.sort_by(&RoomSummary.last_activity/1, DateTime)
    |> Enum.reverse()
  end

  def list_rooms(_viewer_id), do: []

  @doc """
  Every room, newest first — the view used by the read-only API.
  """
  def list_all_rooms do
    Store.list_rooms() |> Enum.reverse()
  end

  @doc """
  Renames a room.
  """
  def rename_room(room_id, name) do
    with {:ok, trimmed} <- validate_room_name(name) do
      translate(Store.rename_room(room_id, trimmed), :room_not_found)
    end
  end

  @doc """
  Deletes a room.
  """
  def delete_room(room_id) when is_binary(room_id) do
    translate(Store.delete_room(room_id), :room_not_found)
  end

  def delete_room(_room_id), do: {:error, :room_not_found}

  @doc """
  Adds a member to a room.
  """
  def add_member(room_id, user_id) do
    with {:ok, room} <- fetch_room(room_id),
         {:ok, user} <- fetch_user(user_id) do
      translate(Store.add_member(room.id, user.id), :room_not_found)
    end
  end

  @doc """
  Removes a member from a room.
  """
  def remove_member(room_id, user_id) do
    with {:ok, room} <- fetch_room(room_id),
         {:ok, user} <- fetch_user(user_id) do
      translate(Store.remove_member(room.id, user.id), :room_not_found)
    end
  end

  @doc """
  Sends a message into a room the sender belongs to.
  """
  def send_message(room_id, user_id, body) do
    with {:ok, room} <- fetch_room(room_id),
         {:ok, user} <- fetch_user(user_id),
         true <- Room.member?(room, user_id),
         {:ok, text} <- validate_body(body) do
      inserted_at = DateTime.utc_now()
      message = Message.new(Store.next_id("m"), room.id, user.id, text, inserted_at)
      {:ok, message} = Store.append_message(message)
      {:ok, message}
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :not_a_member}
    end
  end

  @doc """
  Messages of a room, oldest first.
  """
  def list_messages(room_id) do
    case fetch_room(room_id) do
      {:ok, _room} -> {:ok, Store.list_messages(room_id)}
      {:error, :room_not_found} -> {:error, :room_not_found}
    end
  end

  @doc """
  Cancels a message — only its author may do so.
  """
  def redact_message(message_id, viewer_id) do
    case Store.find_message(message_id) do
      {:error, :not_found} ->
        {:error, :message_not_found}

      {:ok, %Message{redacted: true}} ->
        {:error, :already_redacted}

      {:ok, %Message{author_id: author_id}} ->
        if author_id == viewer_id do
          translate(Store.redact_message(message_id), :message_not_found)
        else
          {:error, :not_author}
        end
    end
  end

  @doc """
  Marks every message in the room as read by the viewer.
  """
  def mark_read(room_id, viewer_id) do
    at = DateTime.utc_now()
    {:ok, at} = Store.mark_read(room_id, viewer_id, at)
    {:ok, at}
  end

  @doc """
  How many messages written by others are still unread.
  """
  def unread_count(room_id, viewer_id) do
    last_read = Store.last_read(room_id, viewer_id)

    others =
      Store.list_messages(room_id)
      |> Enum.filter(fn message -> message.author_id != viewer_id end)

    Enum.count(others, fn message -> unread?(message, last_read) end)
  end

  @doc """
  Read state for the viewer's own messages: `:read` when any other member has
  read up to that message, otherwise `:unread`.
  """
  def read_statuses(room_id, viewer_id) do
    reads = Store.reads_for(room_id)

    Store.list_messages(room_id)
    |> Enum.filter(&(&1.author_id == viewer_id))
    |> Enum.map(fn message -> {message.id, status(message, reads, viewer_id)} end)
    |> Map.new()
  end

  @doc """
  Announces that the viewer is typing.
  """
  def set_typing(room_id, viewer_id, ttl \\ @typing_ttl_seconds) do
    {:ok, until} = Store.set_typing(room_id, viewer_id, ttl)
    {:ok, until}
  end

  @doc """
  Users currently typing in a room.
  """
  def typing_users(room_id) do
    room_id
    |> Store.typing_users()
    |> Enum.map(fn user_id ->
      case fetch_user(user_id) do
        {:ok, user} -> user
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Groups messages by display-timezone day, oldest first.
  """
  def group_by_day(messages, now \\ DateTime.utc_now()) do
    today = Time.local_date(now)
    groups = Enum.reduce(messages, [], &add_to_group(&1, &2, today))

    groups
    |> Enum.map(&reverse_messages/1)
    |> Enum.reverse()
  end

  @doc """
  Subscribes the calling process to changes in one room.
  """
  def subscribe(room_id) when is_binary(room_id) do
    Phoenix.PubSub.subscribe(@pubsub, Store.room_topic(room_id))
  end

  @doc """
  Subscribes the calling process to room-list changes.
  """
  def subscribe_rooms do
    Phoenix.PubSub.subscribe(@pubsub, Store.rooms_topic())
  end

  @doc """
  The maximum message body length, in characters.
  """
  def max_body_length do
    Application.get_env(:line_chat, :max_body_length, 500)
  end

  defp summary(room, viewer_id, now) do
    messages = Store.list_messages(room.id)
    typing = Store.typing_users(room.id, now)

    RoomSummary.new(
      room,
      viewer_id,
      List.last(messages),
      unread_count(room.id, viewer_id),
      typing
    )
  end

  defp join_all_rooms(user_id) do
    for room <- Store.list_rooms() do
      Store.add_member(room.id, user_id)
    end
  end

  defp add_to_group(message, acc, today) do
    date = Time.local_date(message.inserted_at)

    case acc do
      [%{date: ^date} = group | rest] ->
        [%{group | messages: [message | group.messages]} | rest]

      _ ->
        label = Time.date_label(date, today)
        [%{date: date, label: label, messages: [message]} | acc]
    end
  end

  defp reverse_messages(group) do
    %{group | messages: Enum.reverse(group.messages)}
  end

  defp unread?(_message, nil), do: true

  defp unread?(message, last_read) do
    DateTime.compare(message.inserted_at, last_read) == :gt
  end

  defp status(message, reads, viewer_id) do
    others = reads |> Map.delete(viewer_id) |> Map.values()
    inserted_at = message.inserted_at

    if Enum.any?(others, fn at -> DateTime.compare(at, inserted_at) != :lt end) do
      :read
    else
      :unread
    end
  end

  defp validate_body(body) when is_binary(body) do
    body |> String.trim() |> validate_body_text()
  end

  defp validate_body(_body), do: {:error, :invalid_body}

  defp validate_body_text(""), do: {:error, :invalid_body}

  defp validate_body_text(text) do
    if String.length(text) > max_body_length() do
      {:error, :too_long}
    else
      {:ok, text}
    end
  end

  defp validate_room_name(name) when is_binary(name) do
    name |> String.trim() |> validate_trimmed_name()
  end

  defp validate_room_name(_name), do: {:error, :invalid_name}

  defp validate_trimmed_name(""), do: {:error, :invalid_name}

  defp validate_trimmed_name(name) do
    if String.length(name) > @room_name_limit do
      {:error, :invalid_name}
    else
      {:ok, name}
    end
  end

  defp translate({:ok, value}, _reason), do: {:ok, value}
  defp translate({:error, :not_found}, reason), do: {:error, reason}
  defp translate({:error, reason}, _fallback), do: {:error, reason}

  defp guest_name(id, name) when is_binary(name) do
    case String.trim(name) do
      "" -> @default_guest_name <> " " <> id_suffix(id)
      trimmed -> trimmed
    end
  end

  defp guest_name(id, _name), do: @default_guest_name <> " " <> id_suffix(id)

  defp id_suffix(id) do
    id |> String.split("-", parts: 2) |> List.last()
  end

  defp color_for(id) do
    Enum.at(@palette, :erlang.phash2(id, length(@palette)))
  end

  defp color_for_user(nil), do: @default_color
  defp color_for_user(color) when is_binary(color), do: color
  defp color_for_user(_color), do: @default_color
end
