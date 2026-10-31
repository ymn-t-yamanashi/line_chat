defmodule LineChat.Chat.MessageTest do
  use ExUnit.Case, async: true

  alias LineChat.Chat.Message

  @at ~U[2026-10-31 03:00:00Z]

  # Guard clauses reject typed literals at compile time, so wrongly typed
  # arguments are dispatched dynamically.
  defp call(module, function, args), do: apply(module, function, args)

  defp message(body \\ "hello", inserted_at \\ @at) do
    Message.new("m-1", "room-1", "u-1", body, inserted_at)
  end

  describe "new/5" do
    test "starts unredacted" do
      assert message().redacted == false
      refute Message.redacted?(message())
    end

    test "keeps every field" do
      assert %Message{id: "m-1", room_id: "room-1", author_id: "u-1", body: "hello"} =
               message()
    end

    test "stores the timestamp untouched" do
      assert message().inserted_at == @at
    end

    test "accepts an empty body" do
      assert message("").body == ""
    end

    test "does not validate inserted_at" do
      assert message("hello", nil).inserted_at == nil
      assert message("hello", "not-a-timestamp").inserted_at == "not-a-timestamp"
    end

    test "rejects non-binary identity fields" do
      assert_raise FunctionClauseError, fn ->
        call(Message, :new, [1, "room-1", "u-1", "hi", @at])
      end

      assert_raise FunctionClauseError, fn ->
        call(Message, :new, ["m-1", :r, "u-1", "hi", @at])
      end

      assert_raise FunctionClauseError, fn ->
        call(Message, :new, ["m-1", "room-1", 2, "hi", @at])
      end

      assert_raise FunctionClauseError, fn ->
        call(Message, :new, ["m-1", "room-1", "u-1", :hi, @at])
      end
    end
  end

  describe "redact/1" do
    test "flags the message without discarding the body" do
      redacted = Message.redact(message("secret"))
      assert Message.redacted?(redacted)
      assert redacted.body == "secret"
    end

    test "is idempotent" do
      once = Message.redact(message())
      assert Message.redact(once) == once
    end

    test "does not mutate the original message" do
      original = message()
      Message.redact(original)
      refute Message.redacted?(original)
    end

    test "requires a message struct" do
      assert_raise FunctionClauseError, fn -> call(Message, :redact, [%{body: "x"}]) end
      assert_raise FunctionClauseError, fn -> call(Message, :redact, [nil]) end
    end
  end

  describe "displayed_body/1" do
    test "shows the body for a live message" do
      assert Message.displayed_body(message("hello")) == "hello"
    end

    test "shows nothing once redacted" do
      assert Message.displayed_body(Message.redact(message("hello"))) == ""
    end

    test "requires a message struct" do
      assert_raise FunctionClauseError, fn -> call(Message, :displayed_body, [nil]) end
    end
  end
end
