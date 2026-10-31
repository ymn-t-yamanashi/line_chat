defmodule LineChat.ChatCase do
  @moduledoc """
  Test case for the domain layer.

  `LineChat.Chat.Store` is a single in-memory process shared by every test, and
  `LineChat.Application` seeds it on startup, so each test resets it first.
  Anything using this case (or `LineChatWeb.ConnCase`) must run with
  `async: false`.
  """

  use ExUnit.CaseTemplate

  alias LineChat.Chat.{Message, Store}

  using do
    quote do
      alias LineChat.Chat
      alias LineChat.Chat.{Message, Room, RoomSummary, Seeder, Store, Time, User}

      import LineChat.ChatCase
    end
  end

  setup _tags do
    :ok = Store.reset()
    :ok
  end

  @doc "Adds a user and returns the struct."
  def add_user(name, color \\ nil) do
    {:ok, user} = LineChat.Chat.add_user(name, color)
    user
  end

  @doc "Creates a room and returns the struct."
  def create_room(name, member_ids \\ []) do
    {:ok, room} = LineChat.Chat.create_room(name, member_ids)
    room
  end

  @doc "Appends a message with an explicit timestamp, bypassing `Chat.send_message/3`."
  def append_message(room, author, body, inserted_at \\ DateTime.utc_now()) do
    message =
      Message.new(
        Store.next_id("m"),
        room.id,
        author.id,
        body,
        inserted_at
      )

    {:ok, message} = Store.append_message(message)
    message
  end

  @doc "A UTC timestamp `seconds` ago, for fixtures that need real-now relative times."
  def secs_ago(seconds) do
    DateTime.add(DateTime.utc_now(), -seconds, :second)
  end

  @doc "The numeric tail of a store-generated id such as `u-7` -> `7`."
  def id_sequence(id) do
    id |> String.split("-", parts: 2) |> List.last() |> String.to_integer()
  end
end
