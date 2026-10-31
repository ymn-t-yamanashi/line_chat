defmodule LineChat.Chat.RoomTest do
  use ExUnit.Case, async: true

  alias LineChat.Chat.Room

  @created ~U[2026-10-31 03:00:00Z]

  # Guard clauses reject typed literals at compile time, so wrongly typed
  # arguments are dispatched dynamically.
  defp call(module, function, args), do: apply(module, function, args)

  describe "new/3" do
    test "de-duplicates members while keeping order" do
      room = Room.new("room-1", "チーム開発", ["u-1", "u-2", "u-1"])
      assert room.member_ids == ["u-1", "u-2"]
    end

    test "allows an empty member list" do
      assert Room.new("room-1", "Solo", []).member_ids == []
    end

    test "leaves created_at nil by default" do
      assert Room.new("room-1", "Solo", []).created_at == nil
    end
  end

  describe "new/4" do
    test "stores the given created_at" do
      assert Room.new("room-1", "Solo", [], @created).created_at == @created
    end

    test "rejects non-binary ids or names" do
      assert_raise FunctionClauseError, fn -> call(Room, :new, [1, "Solo", []]) end
      assert_raise FunctionClauseError, fn -> call(Room, :new, ["room-1", :solo, []]) end
    end

    test "rejects a non-list member list" do
      assert_raise FunctionClauseError, fn -> call(Room, :new, ["room-1", "Solo", "u-1"]) end
      assert_raise FunctionClauseError, fn -> call(Room, :new, ["room-1", "Solo", nil]) end
    end
  end

  describe "member?/2" do
    test "reports membership" do
      room = Room.new("room-1", "Solo", ["u-1", "u-2"])
      assert Room.member?(room, "u-2")
      refute Room.member?(room, "u-3")
    end

    test "rejects non-binary user ids" do
      room = Room.new("room-1", "Solo", ["u-1"])
      assert_raise FunctionClauseError, fn -> Room.member?(room, nil) end
    end
  end

  describe "add_member/2" do
    test "appends a new member" do
      room = Room.new("room-1", "Solo", ["u-1"])
      assert Room.add_member(room, "u-2").member_ids == ["u-1", "u-2"]
    end

    test "returns the room unchanged when the user already joined" do
      room = Room.new("room-1", "Solo", ["u-1", "u-2"])
      assert Room.add_member(room, "u-1") == room
    end

    test "does not mutate the original room" do
      room = Room.new("room-1", "Solo", ["u-1"])
      Room.add_member(room, "u-2")
      assert room.member_ids == ["u-1"]
    end

    test "rejects non-binary user ids" do
      room = Room.new("room-1", "Solo", ["u-1"])
      assert_raise FunctionClauseError, fn -> Room.add_member(room, 1) end
    end
  end

  describe "remove_member/2" do
    test "removes only the given member" do
      room = Room.new("room-1", "Solo", ["u-1", "u-2", "u-3"])
      assert Room.remove_member(room, "u-2").member_ids == ["u-1", "u-3"]
    end

    test "leaves the room unchanged when the user is absent" do
      room = Room.new("room-1", "Solo", ["u-1"])
      assert Room.remove_member(room, "u-404") == room
    end

    test "rejects non-binary user ids" do
      room = Room.new("room-1", "Solo", ["u-1"])
      assert_raise FunctionClauseError, fn -> Room.remove_member(room, nil) end
    end
  end
end
