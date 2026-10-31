defmodule LineChat.Chat.SeederTest do
  use LineChat.ChatCase, async: false

  # Guarded clauses reject wrongly typed arguments, so dispatch dynamically.
  defp call(module, function, args), do: apply(module, function, args)

  defp seeded do
    {:ok, result} = Seeder.seed()
    result
  end

  defp message_ids_by_author(messages, author_id) do
    messages |> Enum.filter(&(&1.author_id == author_id)) |> Enum.map(& &1.id)
  end

  defp timestamps(messages) do
    Enum.map(messages, & &1.inserted_at)
  end

  defp overlapping_pairs(items) do
    Enum.chunk_every(items, 2, 1, :discard)
  end

  describe "demo data" do
    test "room_names/0 lists the demo rooms in script order" do
      assert Seeder.room_names() == ["チーム開発", "週末の飲み会", "家族"]
    end

    test "message_count/0 counts every demo line" do
      assert Seeder.message_count() == 6

      assert Seeder.message_count() ==
               Enum.sum(Enum.map(Seeder.room_names(), &length(Seeder.script(&1))))
    end

    test "offsets/0 are three increasing moments in the past" do
      offsets = Seeder.offsets()

      assert offsets == [-172_800, -90_000, -3_600]
      assert Enum.all?(offsets, &(&1 < 0))
      assert offsets == Enum.sort(offsets)
      assert Enum.uniq(offsets) == offsets
    end

    test "offsets/0 land on three distinct display-timezone days" do
      now = DateTime.utc_now()

      dates =
        Enum.map(Seeder.offsets(), fn offset ->
          Time.local_date(DateTime.add(now, offset, :second))
        end)

      assert Enum.uniq(dates) == dates
      assert length(dates) == 3
    end

    test "script/1 returns the demo lines for each room name" do
      assert Seeder.script("チーム開発") == ["おはよう!", "仕様を確認しました", "レビューお願いね"]
      assert Seeder.script("週末の飲み会") == ["店を決めたよ", "幹事任せるね"]
      assert Seeder.script("家族") == ["ただいま"]
    end

    test "script/1 returns no lines for an unknown room name" do
      assert Seeder.script("未知のルーム") == []
      assert Seeder.script("") == []
    end

    test "script/1 raises for a non-binary room name" do
      assert_raise FunctionClauseError, fn -> call(Seeder, :script, [nil]) end
      assert_raise FunctionClauseError, fn -> call(Seeder, :script, [42]) end
    end
  end

  describe "seed/0" do
    test "seeds two members, three rooms and six messages" do
      %{users: users, rooms: rooms, messages: messages} = seeded()

      assert length(users) == 2
      assert length(rooms) == 3
      assert messages == Seeder.message_count()

      [alice, bob] = users
      assert alice.name == "アリス"
      assert alice.color == "#67b9e8"
      assert alice.avatar_char == "ア"
      assert bob.name == "ボブ"
      assert bob.color == "#f5b942"
      assert bob.avatar_char == "ボ"

      assert Enum.map(rooms, & &1.name) == Seeder.room_names()
    end

    test "both demo members join every demo room" do
      %{users: [alice, bob], rooms: rooms} = seeded()
      both = [alice.id, bob.id]

      assert Enum.map(rooms, & &1.member_ids) == Enum.map(rooms, fn _room -> both end)

      Enum.each(rooms, fn room ->
        {:ok, fetched} = Chat.fetch_room(room.id)
        assert fetched.member_ids == both
      end)
    end

    test "demo authors alternate, restarting in each room" do
      %{users: [alice, bob], rooms: rooms} = seeded()

      authors =
        Enum.map(rooms, fn room ->
          {:ok, messages} = Chat.list_messages(room.id)
          Enum.map(messages, & &1.author_id)
        end)

      assert authors == [[alice.id, bob.id, alice.id], [alice.id, bob.id], [alice.id]]
    end

    test "demo messages sit in the past and grow within each room" do
      %{rooms: rooms} = seeded()
      now = DateTime.utc_now()

      Enum.each(rooms, fn room ->
        {:ok, messages} = Chat.list_messages(room.id)
        times = timestamps(messages)

        assert Enum.all?(times, fn at -> DateTime.compare(at, now) == :lt end)
        assert times == Enum.sort(times)
        assert Enum.uniq(times) == times
      end)
    end

    test "demo timestamps reuse the offsets in script order" do
      %{rooms: [team, drinking, family]} = seeded()
      {:ok, team_messages} = Chat.list_messages(team.id)
      {:ok, drinking_messages} = Chat.list_messages(drinking.id)
      {:ok, family_messages} = Chat.list_messages(family.id)

      assert timestamps(drinking_messages) == timestamps(team_messages) |> Enum.take(2)
      assert timestamps(family_messages) == timestamps(team_messages) |> Enum.take(1)

      gaps =
        Enum.zip(Seeder.offsets(), Enum.drop(Seeder.offsets(), 1))
        |> Enum.map(fn {from, to} -> to - from end)

      assert Enum.map(overlapping_pairs(team_messages), fn [first, second] ->
               DateTime.diff(second.inserted_at, first.inserted_at)
             end) == gaps
    end

    test "the first demo member has read every room" do
      %{users: [alice, bob], rooms: rooms} = seeded()

      assert Enum.map(rooms, fn room -> Chat.unread_count(room.id, alice.id) end) == [0, 0, 0]
      assert Enum.map(rooms, fn room -> Chat.unread_count(room.id, bob.id) end) == [2, 1, 1]
    end

    test "seeded read receipts mark the second member's messages as read" do
      %{users: [alice, bob], rooms: [team | _]} = seeded()
      {:ok, messages} = Chat.list_messages(team.id)

      alice_statuses = Chat.read_statuses(team.id, alice.id)
      bob_statuses = Chat.read_statuses(team.id, bob.id)

      assert Enum.sort(message_ids_by_author(messages, alice.id)) ==
               Enum.sort(Map.keys(alice_statuses))

      assert Enum.sort(message_ids_by_author(messages, bob.id)) ==
               Enum.sort(Map.keys(bob_statuses))

      assert Enum.all?(Map.values(alice_statuses), &(&1 == :unread))
      assert Enum.all?(Map.values(bob_statuses), &(&1 == :read))
    end

    test "non-members see no rooms but still count messages" do
      %{rooms: rooms} = seeded()
      guest = add_user("ゲスト")

      assert Chat.list_rooms(guest.id) == []
      assert Enum.map(rooms, fn room -> Chat.unread_count(room.id, guest.id) end) == [3, 2, 1]
    end

    test "room lists are ordered by newest activity" do
      %{users: [alice | _], rooms: rooms} = seeded()
      summaries = Chat.list_rooms(alice.id)

      assert Enum.map(summaries, & &1.room.name) == ["チーム開発", "週末の飲み会", "家族"]
      assert Enum.map(summaries, &RoomSummary.preview/1) == ["レビューお願いね", "幹事任せるね", "ただいま"]

      assert Enum.map(Chat.list_all_rooms(), & &1.name) ==
               Enum.reverse(Enum.map(rooms, & &1.name))
    end

    test "the seeded transcript groups into three day labels" do
      %{rooms: [team | _]} = seeded()
      {:ok, messages} = Chat.list_messages(team.id)
      groups = Chat.group_by_day(messages)

      assert length(groups) == 3
      assert Enum.map(groups, & &1.label) == day_labels(messages)
      assert Enum.flat_map(groups, & &1.messages) == messages
    end

    test "seed/0 skips when rooms already exist" do
      %{rooms: rooms} = seeded()
      {:ok, second} = Seeder.seed()

      assert second == %{rooms: 3, status: :already_seeded}
      assert length(Store.list_users()) == 2
      assert length(Store.list_rooms()) == 3
      assert Enum.map(rooms, &length(Store.list_messages(&1.id))) == [3, 2, 1]

      assert Store.list_messages(Enum.at(rooms, 0).id) |> Enum.map(& &1.body) ==
               Seeder.script("チーム開発")
    end

    test "seed/0 seeds again after the store is reset" do
      %{users: [alice, bob]} = seeded()
      :ok = Store.reset()
      {:ok, result} = Seeder.seed()

      assert result.messages == 6
      assert Enum.map(result.rooms, & &1.name) == Seeder.room_names()
      assert id_sequence(Enum.at(result.users, 0).id) > id_sequence(alice.id)
      assert id_sequence(bob.id) == id_sequence(alice.id) + 1
    end
  end

  defp day_labels(messages) do
    now = DateTime.utc_now()
    today = Time.local_date(now)

    Enum.map(messages, fn message ->
      Time.date_label(Time.local_date(message.inserted_at), today)
    end)
  end
end
