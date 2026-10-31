defmodule LineChatWeb.ApiControllerTest do
  @moduledoc """
  Tests for the read-only JSON API.

  `ApiController` promises a JSON view of the chat store, so both collection
  routes must return the documented payloads rather than raising. The payloads
  here are asserted against the same domain functions the LiveViews use, which
  keeps them independent of the demo seed data and of the configured timezone.
  """

  use LineChatWeb.ConnCase, async: false

  alias LineChat.Chat
  alias LineChat.Chat.{Message, Seeder, Store, Time, User}

  @not_found %{"errors" => %{"detail" => "Room not found"}}
  @room_keys ["created_at", "id", "member_ids", "name"]
  @message_keys [
    "author_id",
    "author_name",
    "body",
    "id",
    "inserted_at",
    "redacted",
    "room_id",
    "time_label"
  ]

  defp api_get(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> get(path)
  end

  defp payload(conn) do
    Jason.decode!(conn.resp_body)
  end

  defp content_type(conn) do
    conn.resp_headers |> List.keyfind("content-type", 0) |> elem(1) |> String.split(";") |> hd()
  end

  defp room_by_name(name) do
    Enum.find(Chat.list_all_rooms(), fn room -> room.name == name end)
  end

  defp solo_room(name) do
    {:ok, %User{id: id}} = Chat.add_user("一人用")
    {:ok, room} = Chat.create_room(name, [id])
    room
  end

  defp stored_messages(room_id) do
    {:ok, messages} = Chat.list_messages(room_id)
    messages
  end

  defp expected_room(room) do
    %{
      "id" => room.id,
      "name" => room.name,
      "member_ids" => room.member_ids,
      "created_at" => DateTime.to_iso8601(room.created_at)
    }
  end

  describe "GET /api/rooms" do
    test "lists every room newest first", %{conn: conn} do
      response = api_get(conn, ~p"/api/rooms")
      rooms = payload(response)["rooms"]
      stored = Chat.list_all_rooms()

      assert response.status == 200
      assert content_type(response) == "application/json"

      assert Enum.map(rooms, fn room -> room["id"] end) ==
               Enum.map(stored, fn room -> room.id end)

      assert Enum.map(rooms, fn room -> room["name"] end) ==
               Enum.map(stored, fn room -> room.name end)
    end

    test "exposes exactly the documented room keys", %{conn: conn} do
      rooms = payload(api_get(conn, ~p"/api/rooms"))["rooms"]
      stored = Chat.list_all_rooms()

      assert Enum.all?(rooms, fn room -> Enum.sort(Map.keys(room)) == @room_keys end)

      Enum.zip(rooms, stored)
      |> Enum.each(fn {room, expected} -> assert room == expected_room(expected) end)

      assert Enum.all?(rooms, fn room -> is_binary(room["created_at"]) end)
    end

    test "answers with an empty list when the store holds no rooms", %{conn: conn} do
      :ok = Store.reset()
      response = api_get(conn, ~p"/api/rooms")

      assert response.status == 200
      assert payload(response) == %{"rooms" => []}
    end
  end

  describe "GET /api/rooms/:room_id/messages" do
    test "returns the room alongside its transcript oldest first", %{conn: conn} do
      room = room_by_name("チーム開発")
      response = api_get(conn, ~p"/api/rooms/#{room.id}/messages")
      body = payload(response)
      messages = body["messages"]
      stored = stored_messages(room.id)

      assert response.status == 200
      assert content_type(response) == "application/json"
      assert body["room"] == expected_room(room)
      assert Enum.map(messages, fn message -> message["body"] end) == Seeder.script(room.name)
      assert Enum.map(messages, fn message -> message["author_name"] end) == ["アリス", "ボブ", "アリス"]

      Enum.zip(messages, stored)
      |> Enum.each(fn {message, saved} ->
        assert Enum.sort(Map.keys(message)) == @message_keys
        assert message["id"] == saved.id
        assert message["room_id"] == saved.room_id
        assert message["author_id"] == saved.author_id
        assert message["redacted"] == Message.redacted?(saved)
        assert message["inserted_at"] == DateTime.to_iso8601(saved.inserted_at)
        assert message["time_label"] == Time.time_label(saved.inserted_at)
      end)
    end

    test "labels times as zero-padded local hours", %{conn: conn} do
      room = room_by_name("家族")
      messages = payload(api_get(conn, ~p"/api/rooms/#{room.id}/messages"))["messages"]

      assert Enum.all?(messages, fn message -> message["time_label"] =~ ~r/^\d{2}:\d{2}$/ end)
    end

    test "shows cancelled messages with an empty body", %{conn: conn} do
      room = room_by_name("家族")
      [first | rest] = stored_messages(room.id)
      {:ok, _redacted} = Chat.redact_message(first.id, first.author_id)
      messages = payload(api_get(conn, ~p"/api/rooms/#{room.id}/messages"))["messages"]

      assert hd(messages)["body"] == ""
      assert hd(messages)["redacted"] == true
      assert hd(messages)["author_id"] == first.author_id

      assert Enum.map(Enum.drop(messages, 1), fn message -> message["body"] end) ==
               Enum.map(rest, fn saved -> saved.body end)
    end

    test "names unknown authors as 不明", %{conn: conn} do
      room = room_by_name("チーム開発")
      now = DateTime.utc_now()

      {:ok, _appended} =
        Store.append_message(Message.new(Store.next_id("m"), room.id, "u-gone", "消えた発言者", now))

      message = List.last(payload(api_get(conn, ~p"/api/rooms/#{room.id}/messages"))["messages"])

      assert message["author_id"] == "u-gone"
      assert message["author_name"] == "不明"
      assert message["body"] == "消えた発言者"
      assert message["redacted"] == false
    end

    test "answers with an empty transcript for a room without messages", %{conn: conn} do
      room = solo_room("空の部屋")
      response = api_get(conn, ~p"/api/rooms/#{room.id}/messages")

      assert response.status == 200
      assert payload(response) == %{"room" => expected_room(room), "messages" => []}
    end

    test "answers 404 for a room that does not exist", %{conn: conn} do
      response = api_get(conn, ~p"/api/rooms/room-missing/messages")

      assert response.status == 404
      assert payload(response) == @not_found
      assert content_type(response) == "application/json"
    end

    test "answers 404 once a room has been deleted", %{conn: conn} do
      room = room_by_name("家族")
      {:ok, _deleted} = Chat.delete_room(room.id)
      response = api_get(conn, ~p"/api/rooms/#{room.id}/messages")

      assert response.status == 404
      assert payload(response) == @not_found
    end
  end
end
