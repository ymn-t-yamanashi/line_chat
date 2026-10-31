defmodule LineChat.ChatTest do
  use LineChat.ChatCase, async: false

  alias LineChat.Chat.{Room, RoomSummary, Store, User}

  # Fixed UTC timestamps in JST morning, so day labels never depend on the
  # wall clock. @clock is JST noon on 2026-11-01, which makes 11月1日 今日.
  @clock ~U[2026-11-01 03:00:00Z]
  @ancient ~U[2025-10-28 02:00:00Z]
  @older ~U[2026-10-28 02:00:00Z]
  @two_days_ago ~U[2026-10-30 02:00:00Z]
  @yesterday ~U[2026-10-31 02:00:00Z]
  @today ~U[2026-11-01 02:00:00Z]
  @palette ["#06c755", "#67b9e8", "#f5b942", "#e77fb2", "#9a8ad6", "#59c1c0"]

  # Several facade functions forward to guarded store functions, so wrongly
  # typed arguments are dispatched dynamically.
  defp call(module, function, args), do: apply(module, function, args)

  defp alice, do: add_user("アリス", "#67b9e8")
  defp bob, do: add_user("ボブ")
  defp outsider, do: add_user("外部の人")

  defp group_dates(groups), do: Enum.map(groups, fn group -> group.date end)
  defp group_labels(groups), do: Enum.map(groups, fn group -> group.label end)

  defp group_bodies(groups) do
    Enum.map(groups, fn group -> Enum.map(group.messages, fn message -> message.body end) end)
  end

  describe "create_guest_user/1" do
    test "names a nameless guest after its own id" do
      {:ok, guest} = Chat.create_guest_user()

      assert String.starts_with?(guest.id, "u-")
      assert guest.name == "ゲスト " <> Integer.to_string(id_sequence(guest.id))
    end

    test "trims an explicit guest name" do
      {:ok, guest} = Chat.create_guest_user("  タロー  ")
      assert guest.name == "タロー"
    end

    test "derives the name for blank or missing guest names" do
      for name <- [nil, "", "   "] do
        {:ok, guest} = Chat.create_guest_user(name)
        assert guest.name == "ゲスト " <> Integer.to_string(id_sequence(guest.id))
      end
    end

    test "does not length-check guest names" do
      long = String.duplicate("a", 60)
      {:ok, guest} = Chat.create_guest_user(long)
      assert guest.name == long
    end

    test "assigns a palette colour" do
      {:ok, guest} = Chat.create_guest_user()
      assert guest.color in @palette
    end

    test "joins every room that exists at creation time" do
      member = alice()
      first = create_room("一組", [member.id])
      other = bob()
      second = create_room("二組", [other.id])
      {:ok, guest} = Chat.create_guest_user()

      {:ok, joined_first} = Chat.fetch_room(first.id)
      {:ok, joined_second} = Chat.fetch_room(second.id)

      assert Room.member?(joined_first, guest.id)
      assert Room.member?(joined_second, guest.id)
      assert Chat.list_rooms(guest.id) |> length() == 2
    end

    test "does not join rooms created later" do
      {:ok, guest} = Chat.create_guest_user()
      later = create_room("後組", [alice().id])

      refute Room.member?(later, guest.id)
      assert Chat.list_rooms(guest.id) == []
    end

    test "is stored as a user" do
      {:ok, guest} = Chat.create_guest_user()
      assert Chat.fetch_user(guest.id) == {:ok, guest}
    end
  end

  describe "add_user/2" do
    test "trims the name and allocates an id" do
      user = add_user("  キャロル  ")

      assert user.name == "キャロル"
      assert String.starts_with?(user.id, "u-")
    end

    test "defaults the avatar colour" do
      assert add_user("アリス").color == "#06c755"
      assert add_user("アリス", "#f5b942").color == "#f5b942"
      assert add_user("アリス", :red).color == "#06c755"
    end

    test "rejects blank or non-binary names" do
      assert Chat.add_user("") == {:error, :invalid_name}
      assert Chat.add_user("   ") == {:error, :invalid_name}
      assert Chat.add_user(nil) == {:error, :invalid_name}
      assert Chat.add_user(:name) == {:error, :invalid_name}
    end

    test "accepts 50 characters and rejects 51" do
      assert add_user(String.duplicate("a", 50)).name == String.duplicate("a", 50)
      assert Chat.add_user(String.duplicate("a", 51)) == {:error, :invalid_name}
    end
  end

  describe "users" do
    test "fetch_user/1 reports missing and invalid ids" do
      assert Chat.fetch_user("u-ghost") == {:error, :user_not_found}
      assert Chat.fetch_user(nil) == {:error, :user_not_found}
    end

    test "list_users/0 is newest first" do
      first = add_user("一人目")
      second = add_user("二人目")

      assert Enum.map(Chat.list_users(), fn user -> user.id end) == [second.id, first.id]
    end
  end

  describe "create_room/2" do
    test "trims the name and records a creation time" do
      room = create_room("  チーム開発  ", [alice().id, bob().id])

      assert room.name == "チーム開発"
      assert String.starts_with?(room.id, "room-")
      assert DateTime.diff(DateTime.utc_now(), room.created_at) >= 0
      assert DateTime.diff(DateTime.utc_now(), room.created_at) < 5
    end

    test "de-duplicates members while keeping order" do
      alice_user = alice()
      bob_user = bob()
      room = create_room("重複", [alice_user.id, bob_user.id, alice_user.id])

      assert room.member_ids == [alice_user.id, bob_user.id]
    end

    test "validates the name before the members" do
      assert Chat.create_room("") == {:error, :invalid_name}
      assert Chat.create_room("   ", [alice().id]) == {:error, :invalid_name}
      assert Chat.create_room(nil, [alice().id]) == {:error, :invalid_name}
      assert Chat.create_room(String.duplicate("a", 51)) == {:error, :invalid_name}
    end

    test "rejects an empty member list" do
      assert Chat.create_room("無人", []) == {:error, :invalid_members}
      assert Chat.create_room("無人") == {:error, :invalid_members}
    end

    test "raises when members are not a list" do
      assert_raise FunctionClauseError, fn -> call(Chat, :create_room, ["組", "u-alice"]) end
    end
  end

  describe "rooms" do
    test "fetch_room/1 reports missing and invalid ids" do
      assert Chat.fetch_room("room-ghost") == {:error, :room_not_found}
      assert Chat.fetch_room(nil) == {:error, :room_not_found}
    end

    test "list_all_rooms/0 is newest first" do
      first = create_room("先", [alice().id])
      second = create_room("後", [alice().id])

      assert Enum.map(Chat.list_all_rooms(), fn room -> room.id end) == [second.id, first.id]
    end

    test "list_rooms/1 keeps only rooms the viewer belongs to" do
      viewer = alice()
      _mine = create_room("参加組", [viewer.id])
      theirs = create_room("他人組", [bob().id])

      names = Enum.map(Chat.list_rooms(viewer.id), fn summary -> summary.room.name end)

      assert names == ["参加組"]
      refute Enum.any?(names, fn name -> name == theirs.name end)

      assert Enum.all?(Chat.list_rooms(viewer.id), fn summary ->
               summary.viewer_id == viewer.id
             end)
    end

    test "list_rooms/1 sorts by newest activity" do
      viewer = alice()
      quiet = create_room("静かな組", [viewer.id])
      busy = create_room("活跃的組", [viewer.id])
      append_message(quiet, viewer, "昔のメッセージ", @two_days_ago)
      append_message(busy, viewer, "新しいメッセージ", @today)

      assert Enum.map(Chat.list_rooms(viewer.id), fn s -> s.room.name end) ==
               ["活跃的組", "静かな組"]
    end

    test "list_rooms/1 summarises preview and unread count" do
      viewer = alice()
      other = bob()
      room = create_room("プレビュー組", [viewer.id, other.id])
      long = String.duplicate("長", 30)
      at = secs_ago(120)
      append_message(room, other, long, at)

      [summary] = Chat.list_rooms(viewer.id)

      assert RoomSummary.preview(summary) == String.slice(long, 0, 28) <> "…"
      assert summary.unread_count == 1
      assert RoomSummary.last_activity(summary) == at
    end

    test "list_rooms/1 ignores non-binary viewer ids" do
      create_room("組", [alice().id])

      assert Chat.list_rooms(nil) == []
      assert Chat.list_rooms(:viewer) == []
    end

    test "rename_room/2 updates the stored room" do
      viewer = alice()
      room = create_room("旧名", [viewer.id])
      {:ok, renamed} = Chat.rename_room(room.id, "  新名  ")

      assert renamed.id == room.id
      assert renamed.name == "新名"
      {:ok, fetched} = Chat.fetch_room(room.id)
      assert fetched.name == "新名"
      assert fetched.member_ids == [viewer.id]
    end

    test "rename_room/2 rejects invalid names without touching the room" do
      room = create_room("旧名", [alice().id])

      assert Chat.rename_room(room.id, "") == {:error, :invalid_name}
      assert Chat.rename_room(room.id, String.duplicate("a", 51)) == {:error, :invalid_name}
      assert Chat.fetch_room(room.id) == {:ok, room}
    end

    test "rename_room/2 reports missing rooms" do
      assert Chat.rename_room("room-ghost", "新名") == {:error, :room_not_found}
    end

    test "rename_room/2 raises for non-binary room ids because it is unguarded" do
      assert_raise FunctionClauseError, fn -> call(Chat, :rename_room, [nil, "新名"]) end
    end

    test "delete_room/1 returns the deleted id" do
      room = create_room("削除組", [alice().id])

      assert Chat.delete_room(room.id) == {:ok, room.id}
      assert Chat.fetch_room(room.id) == {:error, :room_not_found}
      assert Chat.list_messages(room.id) == {:error, :room_not_found}
    end

    test "delete_room/1 reports missing and invalid ids" do
      assert Chat.delete_room("room-ghost") == {:error, :room_not_found}
      assert Chat.delete_room(nil) == {:error, :room_not_found}
    end

    test "add_member/2 and remove_member/2 update membership" do
      viewer = alice()
      room = create_room("組", [viewer.id])
      guest = outsider()

      {:ok, added} = Chat.add_member(room.id, guest.id)
      assert added.member_ids == [viewer.id, guest.id]

      {:ok, removed} = Chat.remove_member(room.id, guest.id)
      assert removed.member_ids == [viewer.id]
      {:ok, fetched} = Chat.fetch_room(room.id)
      assert fetched.name == room.name
      assert fetched.member_ids == [viewer.id]
    end

    test "member changes report missing rooms and users" do
      room = create_room("組", [alice().id])

      assert Chat.add_member("room-ghost", alice().id) == {:error, :room_not_found}
      assert Chat.add_member(room.id, "u-ghost") == {:error, :user_not_found}
      assert Chat.remove_member("room-ghost", alice().id) == {:error, :room_not_found}
      assert Chat.remove_member(room.id, "u-ghost") == {:error, :user_not_found}
    end
  end

  describe "send_message/3" do
    test "stores a trimmed body with a fresh timestamp" do
      sender = alice()
      room = create_room("組", [sender.id])

      {:ok, message} = Chat.send_message(room.id, sender.id, "  おはよう!  ")

      assert message.body == "おはよう!"
      assert message.room_id == room.id
      assert message.author_id == sender.id
      assert message.redacted == false
      assert DateTime.diff(DateTime.utc_now(), message.inserted_at) >= 0
    end

    test "appends messages oldest first" do
      sender = alice()
      room = create_room("組", [sender.id])

      {:ok, first} = Chat.send_message(room.id, sender.id, "一番目")
      {:ok, second} = Chat.send_message(room.id, sender.id, "二番目")

      assert Chat.list_messages(room.id) == {:ok, [first, second]}
    end

    test "checks the room before the sender" do
      assert Chat.send_message("room-ghost", alice().id, "hello") == {:error, :room_not_found}
      assert Chat.send_message("room-ghost", "u-ghost", "hello") == {:error, :room_not_found}
    end

    test "checks the sender before membership" do
      room = create_room("組", [bob().id])

      assert Chat.send_message(room.id, "u-ghost", "hello") == {:error, :user_not_found}
      assert Chat.send_message(room.id, outsider().id, "hello") == {:error, :not_a_member}
    end

    test "checks membership before the body" do
      room = create_room("組", [bob().id])

      assert Chat.send_message(room.id, alice().id, "") == {:error, :not_a_member}
    end

    test "rejects blank and non-binary bodies" do
      sender = alice()
      room = create_room("組", [sender.id])

      assert Chat.send_message(room.id, sender.id, "") == {:error, :invalid_body}
      assert Chat.send_message(room.id, sender.id, "   ") == {:error, :invalid_body}
      assert Chat.send_message(room.id, sender.id, nil) == {:error, :invalid_body}
      assert Chat.send_message(room.id, sender.id, :text) == {:error, :invalid_body}
    end

    test "accepts exactly the limit and rejects one character more" do
      sender = alice()
      room = create_room("組", [sender.id])
      limit = Chat.max_body_length()

      assert Chat.max_body_length() == 500
      {:ok, message} = Chat.send_message(room.id, sender.id, String.duplicate("あ", limit))
      assert String.length(message.body) == limit

      assert Chat.send_message(room.id, sender.id, String.duplicate("あ", limit + 1)) ==
               {:error, :too_long}
    end

    test "list_messages/1 returns an empty list for an empty room" do
      room = create_room("空組", [alice().id])
      assert Chat.list_messages(room.id) == {:ok, []}
    end
  end

  describe "redact_message/2" do
    test "only the author can redact" do
      author = alice()
      other = bob()
      room = create_room("組", [author.id, other.id])
      {:ok, message} = Chat.send_message(room.id, author.id, "消して")

      assert Chat.redact_message(message.id, other.id) == {:error, :not_author}
      {:ok, redacted} = Chat.redact_message(message.id, author.id)

      assert redacted.redacted == true
      assert redacted.body == "消して"
      assert Message.displayed_body(redacted) == ""
    end

    test "cannot redact twice" do
      author = alice()
      room = create_room("組", [author.id])
      {:ok, message} = Chat.send_message(room.id, author.id, "二度と")

      assert {:ok, _} = Chat.redact_message(message.id, author.id)
      assert Chat.redact_message(message.id, author.id) == {:error, :already_redacted}
    end

    test "reports missing messages" do
      author = alice()
      room = create_room("組", [author.id])
      {:ok, message} = Chat.send_message(room.id, author.id, "本文")

      assert Chat.redact_message(message.id <> "-x", author.id) ==
               {:error, :message_not_found}

      assert Chat.redact_message("m-ghost", author.id) == {:error, :message_not_found}
    end

    test "redaction shows up in the room preview" do
      author = alice()
      room = create_room("組", [author.id])
      {:ok, message} = Chat.send_message(room.id, author.id, "本文")
      {:ok, _} = Chat.redact_message(message.id, author.id)

      [summary] = Chat.list_rooms(author.id)
      assert RoomSummary.preview(summary) == "メッセージを取り消しました"
    end
  end

  describe "read receipts" do
    test "mark_read/2 records a timestamp and clears unread counts" do
      viewer = alice()
      other = bob()
      room = create_room("組", [viewer.id, other.id])
      append_message(room, other, "既読にして", secs_ago(30))

      {:ok, at} = Chat.mark_read(room.id, viewer.id)

      assert DateTime.diff(DateTime.utc_now(), at) >= 0
      assert Chat.unread_count(room.id, viewer.id) == 0
      assert Store.last_read(room.id, viewer.id) == at
    end

    test "unread_count/2 counts only other authors" do
      viewer = alice()
      other = bob()
      room = create_room("組", [viewer.id, other.id])
      append_message(room, viewer, "自分のメッセージ", @older)
      append_message(room, other, "他人のメッセージ", @older)

      assert Chat.unread_count(room.id, viewer.id) == 1
    end

    test "unread_count/2 counts messages newer than the receipt" do
      viewer = alice()
      other = bob()
      room = create_room("組", [viewer.id, other.id])
      append_message(room, other, "読む前", @older)
      {:ok, _} = Chat.mark_read(room.id, viewer.id)
      append_message(room, other, "読んだ後", @today)

      assert Chat.unread_count(room.id, viewer.id) == 1
    end

    test "read_statuses/2 covers the viewer's own messages" do
      viewer = alice()
      other = bob()
      room = create_room("組", [viewer.id, other.id])
      mine = append_message(room, viewer, "自分の", @older)
      theirs = append_message(room, other, "他人の", @today)
      {:ok, _} = Chat.mark_read(room.id, other.id)

      assert Chat.read_statuses(room.id, viewer.id) == %{mine.id => :read}
      refute Map.has_key?(Chat.read_statuses(room.id, viewer.id), theirs.id)
    end

    test "read_statuses/2 stays unread until another member reads" do
      viewer = alice()
      other = bob()
      room = create_room("組", [viewer.id, other.id])
      mine = append_message(room, viewer, "未読のまま", @today)

      assert Chat.read_statuses(room.id, viewer.id) == %{mine.id => :unread}
    end

    test "read_statuses/2 is coarse: one late receipt marks earlier messages" do
      viewer = alice()
      other = bob()
      room = create_room("組", [viewer.id, other.id])
      early = append_message(room, viewer, "古い", secs_ago(120))
      late = append_message(room, viewer, "新しい", secs_ago(60))
      {:ok, _} = Chat.mark_read(room.id, other.id)

      assert Chat.read_statuses(room.id, viewer.id) == %{early.id => :read, late.id => :read}
    end
  end

  describe "typing hints" do
    test "set_typing/3 returns the expiry time" do
      room = create_room("組", [alice().id])
      viewer = alice()

      {:ok, until} = Chat.set_typing(room.id, viewer.id)
      assert DateTime.diff(until, DateTime.utc_now()) > 0
      assert Chat.typing_users(room.id) == [viewer]
    end

    test "typing entries expire" do
      room = create_room("組", [alice().id])
      {:ok, _until} = Chat.set_typing(room.id, alice().id, -1)

      assert Chat.typing_users(room.id) == []
    end

    test "typing_users/1 drops ids that no longer resolve" do
      user = alice()
      room = create_room("組", [user.id])
      {:ok, _until} = Chat.set_typing(room.id, "u-ghost", 60)
      {:ok, _until} = Chat.set_typing(room.id, user.id, 60)

      assert Chat.typing_users(room.id) == [user]
    end
  end

  describe "group_by_day/2" do
    test "returns no groups for an empty transcript" do
      assert Chat.group_by_day([], @clock) == []
    end

    test "labels days relative to the clock" do
      messages = [
        append_message(%Room{id: "r", name: "組"}, alice(), "昔", @ancient),
        append_message(%Room{id: "r", name: "組"}, alice(), "一昨日より古い", @older),
        append_message(%Room{id: "r", name: "組"}, alice(), "一昨日", @two_days_ago),
        append_message(%Room{id: "r", name: "組"}, alice(), "昨日", @yesterday),
        append_message(%Room{id: "r", name: "組"}, alice(), "今日", @today)
      ]

      groups = Chat.group_by_day(messages, @clock)

      assert group_labels(groups) ==
               ["2025年10月28日 (火)", "10月28日 (水)", "一昨日", "昨日", "今日"]

      assert group_dates(groups) == [
               ~D[2025-10-28],
               ~D[2026-10-28],
               ~D[2026-10-30],
               ~D[2026-10-31],
               ~D[2026-11-01]
             ]

      assert group_bodies(groups) == [["昔"], ["一昨日より古い"], ["一昨日"], ["昨日"], ["今日"]]
    end

    test "merges same-day messages in chronological order" do
      sender = alice()
      room = create_room("組", [sender.id])
      morning = append_message(room, sender, "朝", @today)
      evening = append_message(room, sender, "夜", ~U[2026-11-01 12:00:00Z])

      [group] = Chat.group_by_day([morning, evening], @clock)

      assert group.label == "今日"
      assert group.messages == [morning, evening]
    end

    test "keeps a single group when input is already grouped by day" do
      sender = alice()
      room = create_room("組", [sender.id])
      day_one = append_message(room, sender, "一", @today)
      day_two = append_message(room, sender, "二", ~U[2026-11-01 12:00:00Z])
      yesterday = append_message(room, sender, "三", @yesterday)

      groups = Chat.group_by_day([day_one, day_two, yesterday], @clock)

      assert group_labels(groups) == ["今日", "昨日"]
      assert group_bodies(groups) == [["一", "二"], ["三"]]
    end

    test "does not merge a day once a newer day has been opened" do
      sender = alice()
      room = create_room("組", [sender.id])
      today_first = append_message(room, sender, "今日の朝", @today)
      tomorrow = append_message(room, sender, "明日", ~U[2026-11-02 02:00:00Z])
      today_second = append_message(room, sender, "今日の夜", ~U[2026-11-01 12:00:00Z])

      groups = Chat.group_by_day([today_first, tomorrow, today_second], @clock)

      assert group_labels(groups) == ["今日", "11月2日 (月)", "今日"]
      assert group_bodies(groups) == [["今日の朝"], ["明日"], ["今日の夜"]]
    end

    test "newest-first input produces descending groups" do
      sender = alice()
      room = create_room("組", [sender.id])
      morning = append_message(room, sender, "朝", @today)
      evening = append_message(room, sender, "夜", ~U[2026-11-01 12:00:00Z])

      [group] = Chat.group_by_day([evening, morning], @clock)

      assert group_bodies([group]) == [["夜", "朝"]]
    end

    test "defaults the clock to now" do
      sender = alice()
      room = create_room("組", [sender.id])
      {:ok, message} = Chat.send_message(room.id, sender.id, "いま")

      [group] = Chat.group_by_day([message])
      assert group.date == Time.local_date(message.inserted_at)
      assert group.label == "今日"
    end
  end

  describe "subscriptions" do
    test "subscribe/1 delivers room events" do
      sender = alice()
      room = create_room("組", [sender.id])
      :ok = Chat.subscribe(room.id)

      {:ok, message} = Chat.send_message(room.id, sender.id, "届く")
      assert_receive {:line_chat, :message_created, ^message}
    end

    test "subscribe/1 delivers membership and deletion events" do
      viewer = alice()
      guest = outsider()
      room = create_room("組", [viewer.id])
      :ok = Chat.subscribe(room.id)
      room_id = room.id

      {:ok, updated} = Chat.add_member(room.id, guest.id)
      assert_receive {:line_chat, :room_updated, ^updated}

      assert Chat.delete_room(room_id) == {:ok, room_id}
      assert_receive {:line_chat, :room_deleted, ^room_id}
    end

    test "subscribe_rooms/0 delivers room-list events" do
      :ok = Chat.subscribe_rooms()
      viewer = alice()
      guest = outsider()
      room = create_room("組", [viewer.id])

      assert_receive {:line_chat, :rooms_changed}

      {:ok, updated} = Chat.add_member(room.id, guest.id)
      assert updated.member_ids == [viewer.id, guest.id]
      assert_receive {:line_chat, :rooms_changed}

      {:ok, _message} = Chat.send_message(room.id, viewer.id, "追記")
      assert_receive {:line_chat, :rooms_changed}

      refute_receive {:line_chat, :room_updated, ^updated}
    end

    test "subscribe/1 raises for non-binary room ids" do
      assert_raise FunctionClauseError, fn -> call(Chat, :subscribe, [nil]) end
    end
  end

  describe "store passthrough" do
    test "exposes users and rooms from the store" do
      user = add_user("アリス")
      room = create_room("組", [user.id])

      assert Chat.list_users() == Store.list_users()
      assert Chat.list_all_rooms() == Enum.reverse(Store.list_rooms())
      assert Chat.list_messages(room.id) == {:ok, Store.list_messages(room.id)}
    end

    test "typing users are resolved into structs" do
      room = create_room("組", [alice().id])
      {:ok, _} = Chat.set_typing(room.id, alice().id, 60)

      assert Enum.all?(Chat.typing_users(room.id), fn user -> match?(%User{}, user) end)
    end
  end
end
