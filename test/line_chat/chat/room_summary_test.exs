defmodule LineChat.Chat.RoomSummaryTest do
  use ExUnit.Case, async: true

  alias LineChat.Chat.{Message, Room, RoomSummary, Time}

  @at ~U[2026-10-31 03:00:00Z]
  @created ~U[2026-10-30 03:00:00Z]

  defp room(created_at \\ @created) do
    Room.new("room-1", "チーム開発", ["u-1", "u-2"], created_at)
  end

  defp message(body, inserted_at \\ @at) do
    Message.new("m-1", "room-1", "u-2", body, inserted_at)
  end

  describe "new/4" do
    test "defaults the typing list to empty" do
      summary = RoomSummary.new(room(), "u-1", nil, 0)
      assert summary.typing_user_ids == []
    end

    test "stores every field" do
      summary = RoomSummary.new(room(), "u-1", message("hi"), 3, ["u-2"])
      assert summary.viewer_id == "u-1"
      assert summary.unread_count == 3
      assert summary.typing_user_ids == ["u-2"]
      assert summary.last_message.body == "hi"
    end
  end

  describe "preview/1" do
    test "says so when a room has no messages yet" do
      assert RoomSummary.preview(RoomSummary.new(room(), "u-1", nil, 0)) ==
               "メッセージはまだありません"
    end

    test "says so when the last message was redacted" do
      summary = RoomSummary.new(room(), "u-1", Message.redact(message("hi")), 0)
      assert RoomSummary.preview(summary) == "メッセージを取り消しました"
    end

    test "shows a short body unchanged" do
      assert RoomSummary.preview(RoomSummary.new(room(), "u-1", message("こんにちは"), 0)) ==
               "こんにちは"
    end

    test "leaves a body of exactly the preview length alone" do
      body = String.duplicate("あ", 28)
      summary = RoomSummary.new(room(), "u-1", message(body), 0)
      assert RoomSummary.preview(summary) == body
    end

    test "truncates longer bodies and adds an ellipsis" do
      body = String.duplicate("あ", 29)
      summary = RoomSummary.new(room(), "u-1", message(body), 0)
      assert RoomSummary.preview(summary) == String.slice(body, 0, 28) <> "…"
      assert String.length(RoomSummary.preview(summary)) == 29
    end

    test "counts graphemes rather than bytes" do
      body = String.duplicate("あ", 30)
      summary = RoomSummary.new(room(), "u-1", message(body), 0)
      assert RoomSummary.preview(summary) == String.duplicate("あ", 28) <> "…"
    end

    test "shows an empty body as empty" do
      assert RoomSummary.preview(RoomSummary.new(room(), "u-1", message(""), 0)) == ""
    end
  end

  describe "last_activity/1" do
    test "uses the last message timestamp" do
      assert RoomSummary.last_activity(RoomSummary.new(room(), "u-1", message("hi"), 0)) == @at
    end

    test "falls back to the room's created_at" do
      assert RoomSummary.last_activity(RoomSummary.new(room(), "u-1", nil, 0)) == @created
    end

    test "falls back to now when the room has no created_at" do
      summary = RoomSummary.new(room(nil), "u-1", nil, 0)

      assert DateTime.diff(DateTime.utc_now(), RoomSummary.last_activity(summary), :second) <
               2
    end

    test "drives the day label of the last message" do
      summary = RoomSummary.new(room(), "u-1", message("hi"), 0)
      at = RoomSummary.last_activity(summary)

      assert Time.date_label(Time.local_date(at), Time.local_date(DateTime.utc_now())) in [
               "今日",
               "昨日",
               "一昨日"
             ]
    end
  end
end
