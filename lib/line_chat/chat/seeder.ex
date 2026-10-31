defmodule LineChat.Chat.Seeder do
  @moduledoc """
  Populates the store with demo data so a freshly started server shows a
  LINE-like transcript right away. Idempotent: it skips when rooms exist.
  """

  alias LineChat.Chat
  alias LineChat.Chat.{Message, Store}

  @hour 3_600
  @day 86_400
  @two_days 2 * @day

  @offsets [-@two_days, -@day - @hour, -@hour]

  @scripts [
    {"チーム開発", ["おはよう!", "仕様を確認しました", "レビューお願いね"]},
    {"週末の飲み会", ["店を決めたよ", "幹事任せるね"]},
    {"家族", ["ただいま"]}
  ]

  @doc """
  Seeds two members, three rooms and messages spread over three days so the
  day separators are visible in the transcript.
  """
  def seed do
    case Store.list_rooms() do
      [] -> {:ok, seed_all()}
      rooms -> {:ok, %{rooms: length(rooms), status: :already_seeded}}
    end
  end

  @doc """
  The demo lines for a room name, oldest first.
  """
  def script(name) when is_binary(name) do
    case Enum.find(scripts(), fn {room_name, _lines} -> room_name == name end) do
      {_name, lines} -> lines
      nil -> []
    end
  end

  @doc """
  The demo room names.
  """
  def room_names do
    Enum.map(scripts(), fn {name, _lines} -> name end)
  end

  @doc """
  How many messages the demo transcript contains.
  """
  def message_count do
    Enum.reduce(scripts(), 0, fn {_name, lines}, total -> total + length(lines) end)
  end

  @doc """
  How long ago each demo message sits, oldest first, in seconds.
  """
  def offsets, do: @offsets

  defp seed_all do
    now = DateTime.utc_now()
    {:ok, alice} = Chat.add_user("アリス", "#67b9e8")
    {:ok, bob} = Chat.add_user("ボブ", "#f5b942")

    rooms =
      Enum.map(scripts(), fn {name, _lines} ->
        {:ok, room} = Chat.create_room(name, [alice.id, bob.id])
        room
      end)

    Enum.each(rooms, fn room -> seed_room(room, alice, bob, now) end)
    Enum.each(rooms, fn room -> Chat.mark_read(room.id, alice.id) end)

    %{users: [alice, bob], rooms: rooms, messages: message_count()}
  end

  defp seed_room(room, alice, bob, now) do
    lines = script(room.name)

    lines
    |> Enum.with_index()
    |> Enum.each(fn {body, index} ->
      author = Enum.at([alice, bob], rem(index, 2))
      insert(room.id, author.id, body, DateTime.add(now, Enum.at(offsets(), index), :second))
    end)
  end

  defp insert(room_id, author_id, body, inserted_at) do
    message = Message.new(Store.next_id("m"), room_id, author_id, body, inserted_at)
    {:ok, _message} = Store.append_message(message)
  end

  defp scripts, do: @scripts
end
