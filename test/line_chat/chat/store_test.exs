defmodule LineChat.Chat.StoreTest do
  use LineChat.ChatCase, async: false

  alias LineChat.Chat.{Message, Room, Store, User}
  alias LineChat.PubSub

  @at ~U[2026-10-31 03:00:00Z]
  @later ~U[2026-10-31 04:00:00Z]

  # Several store functions guard on structs and binaries, which the type
  # checker rejects for literals, so they are dispatched dynamically.
  defp call(module, function, args), do: apply(module, function, args)

  defp subscribe(topic), do: Phoenix.PubSub.subscribe(PubSub, topic)

  defp alice, do: User.new("u-alice", "アリス", "#67b9e8")
  defp bob, do: User.new("u-bob", "ボブ", "#f5b942")

  defp demo_room, do: Room.new("room-1", "チーム開発", [alice().id, bob().id], @at)

  defp group_room, do: Room.new("room-2", "週末の飲み会", [bob().id], @later)

  defp message(id \\ "m-1", author \\ "u-alice", body \\ "おはよう!", at \\ @at, room_id \\ "room-1") do
    Message.new(id, room_id, author, body, at)
  end

  # `reset/0` clears the data but keeps the id counter, so expectations derive
  # from whatever the counter currently is instead of hardcoding values.
  defp seq(id) do
    id |> String.split("-") |> List.last() |> String.to_integer()
  end

  describe "topics" do
    test "rooms_topic/0 is the shared room-list topic" do
      assert Store.rooms_topic() == "rooms"
    end

    test "room_topic/1 namespaces by room id" do
      assert Store.room_topic("room-1") == "rooms:room-1"
    end

    test "room_topic/1 rejects non-binary ids" do
      assert_raise FunctionClauseError, fn -> call(Store, :room_topic, [:"room-1"]) end
    end
  end

  describe "next_id/1" do
    test "allocates increasing ids for one prefix" do
      first = Store.next_id("u")
      assert String.starts_with?(first, "u-")
      assert Store.next_id("u") == "u-" <> Integer.to_string(seq(first) + 1)
    end

    test "shares one counter across prefixes" do
      user_id = Store.next_id("u")
      room_id = Store.next_id("room")
      message_id = Store.next_id("m")

      assert String.starts_with?(user_id, "u-")
      assert String.starts_with?(room_id, "room-")
      assert String.starts_with?(message_id, "m-")
      assert seq(room_id) == seq(user_id) + 1
      assert seq(message_id) == seq(room_id) + 1
    end

    test "keeps the counter across reset so ids never collide" do
      before = Store.next_id("u")
      :ok = Store.reset()

      assert Store.list_users() == []
      assert Store.next_id("u") == "u-" <> Integer.to_string(seq(before) + 1)
    end

    test "rejects non-binary prefixes" do
      assert_raise FunctionClauseError, fn -> call(Store, :next_id, [:u]) end
    end
  end

  describe "users" do
    test "add_user/1 stores and returns the user" do
      user = alice()
      assert {:ok, ^user} = Store.add_user(user)
      assert Store.fetch_user("u-alice") == {:ok, user}
    end

    test "add_user/1 announces on the rooms topic only" do
      subscribe(Store.rooms_topic())
      subscribe(Store.room_topic("room-1"))
      user = alice()
      assert {:ok, ^user} = Store.add_user(user)
      assert_receive {:line_chat, :user_added, ^user}
      refute_receive {:line_chat, :rooms_changed}
    end

    test "list_users/0 sorts newest first" do
      Store.add_user(alice())
      Store.add_user(bob())
      assert Enum.map(Store.list_users(), fn user -> user.id end) == ["u-bob", "u-alice"]
    end

    test "fetch_user/1 reports missing users" do
      assert Store.fetch_user("u-ghost") == {:error, :not_found}
    end

    test "guards struct input and binary ids" do
      assert_raise FunctionClauseError, fn -> call(Store, :add_user, [%{id: "u-alice"}]) end
      assert_raise FunctionClauseError, fn -> call(Store, :fetch_user, [:"u-alice"]) end
    end
  end

  describe "rooms" do
    test "add_room/1 appends in insertion order" do
      Store.add_room(demo_room())
      Store.add_room(group_room())
      assert Enum.map(Store.list_rooms(), fn room -> room.id end) == ["room-1", "room-2"]
    end

    test "add_room/1 announces on the rooms topic only" do
      subscribe(Store.rooms_topic())
      subscribe(Store.room_topic("room-1"))
      room = demo_room()
      assert {:ok, ^room} = Store.add_room(room)
      assert_receive {:line_chat, :rooms_changed}
      refute_receive {:line_chat, :room_updated, _room}
    end

    test "fetch_room/1 reports missing rooms" do
      assert Store.fetch_room("room-ghost") == {:error, :not_found}
    end

    test "rename_room/2 rewrites the name and keeps the rest" do
      Store.add_room(demo_room())
      assert {:ok, room} = Store.rename_room("room-1", "週末の飲み会")
      assert room.name == "週末の飲み会"
      assert room.member_ids == ["u-alice", "u-bob"]
      assert room.created_at == @at
    end

    test "rename_room/2 broadcasts the list change before the room change" do
      Store.add_room(demo_room())
      subscribe(Store.rooms_topic())
      subscribe(Store.room_topic("room-1"))
      assert {:ok, room} = Store.rename_room("room-1", "改名しました")
      assert_receive {:line_chat, :rooms_changed}
      assert_receive {:line_chat, :room_updated, ^room}
    end

    test "rename_room/2 reports missing rooms without broadcasting" do
      subscribe(Store.rooms_topic())
      assert Store.rename_room("room-ghost", "名前") == {:error, :room_not_found}
      refute_receive {:line_chat, :rooms_changed}
    end

    test "delete_room/1 replies with the id rather than the struct" do
      Store.add_room(demo_room())
      assert Store.delete_room("room-1") == {:ok, "room-1"}
      assert Store.list_rooms() == []
    end

    test "delete_room/1 drops messages, receipts and typing hints" do
      Store.add_room(demo_room())
      Store.append_message(message())
      Store.mark_read("room-1", "u-bob", @at)
      Store.set_typing("room-1", "u-bob", 60)
      assert {:ok, "room-1"} = Store.delete_room("room-1")
      assert Store.list_messages("room-1") == []
      assert Store.reads_for("room-1") == %{}
      assert Store.typing_users("room-1", @later) == []
      assert Store.find_message("m-1") == {:error, :not_found}
    end

    test "delete_room/1 broadcasts the list change before the room change" do
      Store.add_room(demo_room())
      subscribe(Store.rooms_topic())
      subscribe(Store.room_topic("room-1"))
      assert {:ok, "room-1"} = Store.delete_room("room-1")
      assert_receive {:line_chat, :rooms_changed}
      assert_receive {:line_chat, :room_deleted, "room-1"}
    end

    test "delete_room/1 reports missing rooms" do
      assert Store.delete_room("room-ghost") == {:error, :room_not_found}
    end

    test "add_member/2 de-duplicates while keeping order" do
      Store.add_room(demo_room())
      assert {:ok, room} = Store.add_member("room-1", "u-alice")
      assert room.member_ids == ["u-alice", "u-bob"]
      assert {:ok, room} = Store.add_member("room-1", "u-carol")
      assert room.member_ids == ["u-alice", "u-bob", "u-carol"]
    end

    test "remove_member/2 deletes one member and ignores absent ones" do
      Store.add_room(demo_room())
      assert {:ok, room} = Store.remove_member("room-1", "u-bob")
      assert room.member_ids == ["u-alice"]
      assert {:ok, room} = Store.remove_member("room-1", "u-absent")
      assert room.member_ids == ["u-alice"]
    end

    test "member changes broadcast the list before the room" do
      Store.add_room(demo_room())
      subscribe(Store.rooms_topic())
      subscribe(Store.room_topic("room-1"))
      assert {:ok, room} = Store.add_member("room-1", "u-carol")
      assert_receive {:line_chat, :rooms_changed}
      assert_receive {:line_chat, :room_updated, ^room}
    end

    test "member changes report missing rooms" do
      subscribe(Store.room_topic("room-1"))
      assert Store.add_member("room-ghost", "u-alice") == {:error, :room_not_found}
      assert Store.remove_member("room-ghost", "u-alice") == {:error, :room_not_found}
      refute_receive {:line_chat, :room_updated, _room}
    end

    test "room mutations reject non-binary ids and names" do
      assert_raise FunctionClauseError, fn -> call(Store, :add_room, [%{id: "room-1"}]) end
      assert_raise FunctionClauseError, fn -> call(Store, :fetch_room, [:"room-1"]) end
      assert_raise FunctionClauseError, fn -> call(Store, :rename_room, ["room-1", :name]) end
      assert_raise FunctionClauseError, fn -> call(Store, :delete_room, [:"room-1"]) end
      assert_raise FunctionClauseError, fn -> call(Store, :add_member, [:"room-1", "u-alice"]) end

      assert_raise FunctionClauseError, fn ->
        call(Store, :remove_member, ["room-1", :"u-alice"])
      end
    end
  end

  describe "messages" do
    test "append_message/1 keeps rooms oldest first" do
      Store.add_room(demo_room())
      Store.append_message(message("m-1", "u-alice", "おはよう!", @at))
      Store.append_message(message("m-2", "u-bob", "レビューお願いね", @later))

      assert Enum.map(Store.list_messages("room-1"), fn msg -> msg.body end) == [
               "おはよう!",
               "レビューお願いね"
             ]
    end

    test "append_message/1 broadcasts the room before the list" do
      Store.add_room(demo_room())
      subscribe(Store.room_topic("room-1"))
      subscribe(Store.rooms_topic())
      appended = message()
      assert {:ok, ^appended} = Store.append_message(appended)
      assert_receive {:line_chat, :message_created, ^appended}
      assert_receive {:line_chat, :rooms_changed}
    end

    test "list_messages/0 is empty for unknown rooms" do
      assert Store.list_messages("room-ghost") == []
    end

    test "find_message/1 searches every room" do
      Store.add_room(demo_room())
      Store.add_room(group_room())
      Store.append_message(message("m-1", "u-alice", "おはよう!", @at, "room-1"))
      Store.append_message(message("m-2", "u-bob", "ただいま", @later, "room-2"))
      assert {:ok, %Message{id: "m-2", room_id: "room-2"}} = Store.find_message("m-2")
      assert Store.find_message("m-ghost") == {:error, :not_found}
    end

    test "redact_message/1 flags the stored message but keeps the body" do
      Store.add_room(demo_room())
      Store.append_message(message())
      assert {:ok, redacted} = Store.redact_message("m-1")
      assert redacted.redacted
      assert redacted.body == "おはよう!"
      assert [%Message{redacted: true, body: "おはよう!"}] = Store.list_messages("room-1")
    end

    test "redact_message/1 broadcasts the room only" do
      Store.add_room(demo_room())
      Store.append_message(message())
      subscribe(Store.room_topic("room-1"))
      subscribe(Store.rooms_topic())
      assert {:ok, redacted} = Store.redact_message("m-1")
      assert_receive {:line_chat, :message_redacted, ^redacted}
      refute_receive {:line_chat, :rooms_changed}
    end

    test "redact_message/1 leaves other rooms untouched" do
      Store.add_room(demo_room())
      Store.add_room(group_room())
      Store.append_message(message("m-1", "u-alice", "おはよう!", @at, "room-1"))
      Store.append_message(message("m-2", "u-bob", "ただいま", @later, "room-2"))
      assert {:ok, _redacted} = Store.redact_message("m-1")
      assert [%Message{redacted: false, body: "ただいま"}] = Store.list_messages("room-2")
    end

    test "redact_message/1 reports missing messages" do
      assert Store.redact_message("m-ghost") == {:error, :not_found}
    end

    test "message lookups reject non-binary ids and structs" do
      assert_raise FunctionClauseError, fn ->
        call(Store, :append_message, [%{room_id: "room-1"}])
      end

      assert_raise FunctionClauseError, fn -> call(Store, :list_messages, [:"room-1"]) end
      assert_raise FunctionClauseError, fn -> call(Store, :find_message, [:"m-1"]) end
      assert_raise FunctionClauseError, fn -> call(Store, :redact_message, [:"m-1"]) end
    end
  end

  describe "read receipts" do
    test "mark_read/3 replies with the timestamp and announces on the room topic" do
      subscribe(Store.room_topic("room-1"))
      assert {:ok, at} = Store.mark_read("room-1", "u-alice", @at)
      assert at == @at
      assert_receive {:line_chat, :read_marked, "room-1"}
    end

    test "mark_read/3 defaults to the current time" do
      assert {:ok, at} = Store.mark_read("room-1", "u-alice")
      assert DateTime.compare(at, DateTime.utc_now()) != :gt
    end

    test "last_read/2 keeps the newest receipt" do
      Store.mark_read("room-1", "u-alice", @at)
      Store.mark_read("room-1", "u-alice", @later)
      assert Store.last_read("room-1", "u-alice") == @later
    end

    test "last_read/2 is nil without a receipt" do
      assert Store.last_read("room-1", "u-alice") == nil
      assert Store.last_read("room-ghost", "u-alice") == nil
    end

    test "last_read/2 does not guard its arguments" do
      assert Store.last_read(nil, "u-alice") == nil
    end

    test "reads_for/1 keys receipts by user id" do
      Store.mark_read("room-1", "u-alice", @at)
      Store.mark_read("room-1", "u-bob", @later)
      assert Store.reads_for("room-1") == %{"u-alice" => @at, "u-bob" => @later}
    end

    test "reads_for/1 is empty for unknown rooms" do
      assert Store.reads_for("room-ghost") == %{}
    end

    test "reads_for/1 rejects non-binary ids" do
      assert_raise FunctionClauseError, fn -> call(Store, :reads_for, [:"room-1"]) end
    end
  end

  describe "typing hints" do
    test "set_typing/3 expires after the default ttl" do
      now = DateTime.utc_now()
      assert {:ok, until} = Store.set_typing("room-1", "u-alice")
      assert DateTime.compare(until, DateTime.add(now, 3, :second)) == :gt
      assert DateTime.compare(until, DateTime.add(now, 5, :second)) == :lt
      assert Store.typing_users("room-1", now) == ["u-alice"]
    end

    test "typing_users/2 sorts ids and expires them" do
      Store.set_typing("room-1", "u-bob", 60)
      Store.set_typing("room-1", "u-alice", 60)
      assert Store.typing_users("room-1") == ["u-alice", "u-bob"]
      expired = DateTime.add(DateTime.utc_now(), 61, :second)
      assert Store.typing_users("room-1", expired) == []
    end

    test "a zero ttl is already expired" do
      assert {:ok, until} = Store.set_typing("room-1", "u-alice", 0)
      assert Store.typing_users("room-1", until) == []
    end

    test "typing hints announce on the room topic only" do
      subscribe(Store.rooms_topic())
      subscribe(Store.room_topic("room-1"))
      assert {:ok, _until} = Store.set_typing("room-1", "u-alice", 60)
      assert_receive {:line_chat, :typing_changed, "room-1"}
      refute_receive {:line_chat, :rooms_changed}
    end

    test "typing hints are scoped to their room" do
      Store.add_room(demo_room())
      Store.set_typing("room-2", "u-alice", 60)
      assert Store.typing_users("room-1") == []
      assert Store.typing_users("room-2") == ["u-alice"]
    end

    test "typing_users/2 does not guard its arguments" do
      assert Store.typing_users("room-ghost") == []
      assert Store.typing_users(nil) == []
    end
  end

  describe "reset/0" do
    test "clears users, rooms, messages, receipts and typing hints" do
      Store.add_user(alice())
      Store.add_room(demo_room())
      Store.append_message(message())
      Store.mark_read("room-1", "u-bob", @at)
      Store.set_typing("room-1", "u-bob", 60)
      assert Store.reset() == :ok
      assert Store.list_users() == []
      assert Store.list_rooms() == []
      assert Store.list_messages("room-1") == []
      assert Store.reads_for("room-1") == %{}
      assert Store.typing_users("room-1") == []
    end

    test "init/1 ignores its options and starts empty" do
      assert Store.init([]) == {:ok, %Store{}}
    end
  end
end
