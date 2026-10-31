defmodule LineChatWeb.ApiController do
  @moduledoc """
  Read-only JSON view of the chat store. Nothing here mutates state, so the
  transcript a browser sees through LiveViews is the same data this API shows.
  """

  use LineChatWeb, :controller

  alias LineChat.Chat
  alias LineChat.Chat.{Message, Room, Time}

  def rooms(conn, _params) do
    json(conn, %{rooms: Enum.map(Chat.list_all_rooms(), &room_payload/1)})
  end

  def messages(conn, %{"room_id" => room_id}) do
    with {:ok, room} <- Chat.fetch_room(room_id),
         {:ok, messages} <- Chat.list_messages(room.id) do
      json(conn, %{
        room: room_payload(room),
        messages: Enum.map(messages, &message_payload(&1, names_by_id()))
      })
    else
      {:error, :room_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "Room not found"}})
    end
  end

  defp room_payload(%Room{} = room) do
    %{
      id: room.id,
      name: room.name,
      member_ids: room.member_ids,
      created_at: room.created_at
    }
  end

  defp message_payload(%Message{} = message, names) do
    %{
      id: message.id,
      room_id: message.room_id,
      author_id: message.author_id,
      author_name: Map.get(names, message.author_id, "不明"),
      body: Message.displayed_body(message),
      redacted: Message.redacted?(message),
      inserted_at: DateTime.to_iso8601(message.inserted_at),
      time_label: Time.time_label(message.inserted_at)
    }
  end

  defp names_by_id do
    Chat.list_users() |> Map.new(fn user -> {user.id, user.name} end)
  end
end
