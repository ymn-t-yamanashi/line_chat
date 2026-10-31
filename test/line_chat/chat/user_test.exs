defmodule LineChat.Chat.UserTest do
  use ExUnit.Case, async: true

  alias LineChat.Chat.User

  # Guard clauses reject typed literals at compile time, so wrongly typed
  # arguments are dispatched dynamically.
  defp call(module, function, args), do: apply(module, function, args)

  describe "new/2" do
    test "uses the default LINE green" do
      assert User.new("u-1", "アリス").color == "#06c755"
    end

    test "derives the avatar character from the name" do
      assert User.new("u-1", "アリス").avatar_char == "ア"
    end

    test "keeps the id and name" do
      user = User.new("u-9", "Bob")
      assert %User{id: "u-9", name: "Bob"} = user
    end
  end

  describe "new/3" do
    test "accepts an explicit colour" do
      assert User.new("u-1", "アリス", "#f5b942").color == "#f5b942"
    end

    test "accepts nil as a colour" do
      assert User.new("u-1", "アリス", nil).color == nil
    end

    test "rejects non-binary ids and names" do
      assert_raise FunctionClauseError, fn -> call(User, :new, [1, "アリス"]) end
      assert_raise FunctionClauseError, fn -> call(User, :new, ["u-1", :bob]) end
    end
  end

  describe "avatar_char/1" do
    test "returns the first grapheme" do
      assert User.avatar_char("チーム開発") == "チ"
      assert User.avatar_char("Bob") == "B"
    end

    test "treats an empty name as a question mark" do
      assert User.avatar_char("") == "?"
    end

    test "keeps a leading space as the character" do
      assert User.avatar_char(" 空気") == " "
    end

    test "handles multi-byte characters as single graphemes" do
      assert User.avatar_char("🍺酒吧") == "🍺"
    end

    test "matches the character stored by new/2" do
      assert User.avatar_char("アリス") == User.new("u-1", "アリス").avatar_char
    end

    test "rejects non-binary names" do
      assert_raise FunctionClauseError, fn -> call(User, :avatar_char, [nil]) end
      assert_raise FunctionClauseError, fn -> call(User, :avatar_char, [%User{}]) end
    end
  end
end
