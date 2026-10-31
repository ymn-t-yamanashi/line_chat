defmodule LineChatWeb.RoomLiveTest do
  use LineChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import LineChat.ChatCase

  alias LineChat.Chat
  alias LineChat.Chat.{Room, Seeder, Store, Time, User}
  alias LineChatWeb.Endpoint
  alias LineChatWeb.GuestPlug
  alias Phoenix.LiveView.Utils

  @alice_color "#67b9e8"
  @bob_color "#f5b942"
  @default_color "#06c755"
  @palette ["#06c755", "#67b9e8", "#f5b942", "#e77fb2", "#9a8ad6", "#59c1c0"]
  @day 86_400

  defp sess(conn, user_id) do
    Plug.Test.init_test_session(conn, %{GuestPlug.session_key() => user_id})
  end

  defp find(html, selector) do
    {:ok, document} = Floki.parse_document(html)
    Floki.find(document, selector)
  end

  defp normalize(text) do
    text |> String.replace(~r/\s+/, " ") |> String.trim()
  end

  defp texts(html, selector) do
    html |> find(selector) |> Enum.map(fn node -> Floki.text(node) |> String.trim() end)
  end

  defp collapsed(html, selector) do
    html |> find(selector) |> Enum.map(fn node -> Floki.text(node) |> normalize() end)
  end

  defp count(html, selector), do: html |> find(selector) |> length()

  defp attr(html, selector, name) do
    html |> find(selector) |> List.first() |> Floki.attribute(name) |> List.first()
  end

  defp styles(html, selector) do
    html
    |> find(selector)
    |> Enum.map(fn node -> Floki.attribute(node, "style") |> List.first() end)
  end

  defp named(name) do
    Enum.find(Chat.list_users(), fn user -> user.name == name end)
  end

  defp room_named(name) do
    Enum.find(Chat.list_all_rooms(), fn room -> room.name == name end)
  end

  defp messages_in(room) do
    {:ok, messages} = Chat.list_messages(room.id)
    messages
  end

  defp room_view(conn, user_id, room) do
    {:ok, view, html} = live(sess(conn, user_id), ~p"/rooms/#{room.id}")
    {view, html}
  end

  defp alice, do: named("アリス")
  defp bob, do: named("ボブ")
  defp team, do: room_named("チーム開発")

  defp member_guest do
    {:ok, guest} = Chat.create_guest_user()
    guest
  end

  defp day_labels(messages, now) do
    today = Time.local_date(now)

    messages
    |> Enum.map(fn message -> Time.date_label(Time.local_date(message.inserted_at), today) end)
    |> Enum.uniq()
  end

  defp clock_labels(messages) do
    Enum.map(messages, fn message -> Time.time_label(message.inserted_at) end)
  end

  defp decode_flash(flash) when is_binary(flash), do: Utils.verify_flash(Endpoint, flash)

  describe "opening a room" do
    test "renders the header, transcript and both forms", %{conn: conn} do
      {_view, html} = room_view(conn, alice().id, team())

      assert texts(html, ".screen-title") == ["チーム開発"]
      assert texts(html, ".viewer-note") == ["アリス・2人"]
      assert attr(html, ".back-link", "href") == "/"
      assert texts(html, ".empty-note") == []
      assert count(html, ".day-group") == 3
      assert count(html, ".message-row") == 3
      assert count(html, ".bubble") == 3
      assert count(html, ".bubble--self") == 2
      assert count(html, ".redact-button") == 2
      assert texts(html, ".bubble-body") == ["おはよう!", "仕様を確認しました", "レビューお願いね"]
      assert texts(html, ".bubble-author") == ["アリス", "ボブ", "アリス"]
      assert attr(html, "#room_name", "value") == "チーム開発"
      assert attr(html, "#body", "value") == ""
      assert attr(html, "#body", "placeholder") == "メッセージを入力"
    end

    test "puts the viewer's avatar first and colours authors by identity", %{conn: conn} do
      {_view, html} = room_view(conn, alice().id, team())

      assert count(html, ".avatar") == 4

      assert styles(html, ".avatar") ==
               [
                 "background-color: #{@alice_color}",
                 "background-color: #{@alice_color}",
                 "background-color: #{@bob_color}",
                 "background-color: #{@alice_color}"
               ]

      assert texts(html, ".avatar") == ["ア", "ア", "ボ", "ア"]
    end

    test "shows bob's identity when bob opens the room", %{conn: conn} do
      {_view, html} = room_view(conn, bob().id, team())

      assert texts(html, ".viewer-note") == ["ボブ・2人"]

      assert styles(html, ".avatar") ==
               [
                 "background-color: #{@bob_color}",
                 "background-color: #{@alice_color}",
                 "background-color: #{@bob_color}",
                 "background-color: #{@alice_color}"
               ]

      assert count(html, ".bubble--self") == 1
      assert texts(html, ".read-state") == ["既読"]
    end

    test "marks read receipts once bob reads", %{conn: conn} do
      {view, html} = room_view(conn, alice().id, team())

      assert texts(html, ".read-state") == ["未読", "未読"]
      {:ok, _read} = Chat.mark_read(team().id, bob().id)

      assert texts(render(view), ".read-state") == ["既読", "既読"]
    end

    test "labels each day relative to today and derives every clock label", %{conn: conn} do
      now = DateTime.utc_now()
      {_view, html} = room_view(conn, alice().id, team())
      messages = messages_in(team())

      assert texts(html, ".day-separator") == ["一昨日", "昨日", "今日"]
      assert texts(html, ".day-separator") == day_labels(messages, now)
      assert texts(html, ".bubble-time") == clock_labels(messages)

      assert Enum.all?(texts(html, ".bubble-time"), fn label ->
               Regex.match?(~r/^\d{2}:\d{2}$/u, label)
             end)
    end

    test "spreads the seeded transcript over the demo offsets", %{conn: conn} do
      now = DateTime.utc_now()
      {_view, html} = room_view(conn, alice().id, team())

      derived =
        Enum.map(Seeder.offsets(), fn offset ->
          Time.time_label(DateTime.add(now, offset, :second))
        end)

      assert texts(html, ".bubble-time") == derived
    end

    test "reads the transcript without subscribing on a plain GET", %{conn: conn} do
      guest = member_guest()
      html = sess(conn, guest.id) |> get(~p"/rooms/#{team().id}") |> html_response(200)

      assert texts(html, ".screen-title") == ["チーム開発"]
      assert texts(html, ".viewer-note") == ["#{guest.name}・3人"]
      assert count(html, ".day-group") == 3
      assert texts(html, ".read-state") == []
      assert Chat.unread_count(team().id, guest.id) == 3
    end
  end

  describe "rejecting viewers and rooms" do
    test "redirects a non-member out of the room", %{conn: conn} do
      outsider = add_user("外人")
      assert Chat.unread_count(team().id, outsider.id) == 3

      assert {:error, {:redirect, %{flash: %{"error" => "このルームには参加していません"}, to: "/"}}} =
               live(sess(conn, outsider.id), ~p"/rooms/#{team().id}")

      assert Chat.unread_count(team().id, outsider.id) == 3
    end

    test "redirects a missing room id out of the room", %{conn: conn} do
      assert {:error, {:redirect, %{flash: %{"error" => "ルームが見つかりません"}, to: "/"}}} =
               live(sess(conn, alice().id), ~p"/rooms/room-none")
    end

    test "redirects a plain GET from a room the viewer is not in", %{conn: conn} do
      outsider = add_user("外人")
      conn = sess(conn, outsider.id) |> get(~p"/rooms/#{team().id}")

      assert html_response(conn, 302) =~ "redirected"
      assert redirected_to(conn) == "/"
      assert conn.assigns[:flash] == %{"error" => "このルームには参加していません"}

      followed = conn |> get(~p"/") |> html_response(200)
      assert collapsed(followed, ".flash--error") == ["エラー このルームには参加していません"]
      assert texts(followed, ".flash-title") == ["エラー"]
      assert texts(followed, ".screen-title") == ["ルーム一覧"]
    end

    test "redirects a plain GET for a missing room id", %{conn: conn} do
      conn = sess(conn, alice().id) |> get(~p"/rooms/room-none")

      assert redirected_to(conn) == "/"
      assert conn.assigns[:flash] == %{"error" => "ルームが見つかりません"}

      followed = conn |> get(~p"/") |> html_response(200)
      assert collapsed(followed, ".flash--error") == ["エラー ルームが見つかりません"]
      assert texts(followed, ".flash-title") == ["エラー"]
    end

    test "replaces an unknown session id with a fresh guest", %{conn: conn} do
      {:ok, view, html} = live(sess(conn, "u-does-not-exist"), ~p"/rooms/#{team().id}")
      fresh = Chat.list_users() |> List.first()

      assert {:error, :user_not_found} = Chat.fetch_user("u-does-not-exist")
      assert fresh.name == "ゲスト #{id_sequence(fresh.id)}"
      assert Enum.any?(@palette, fn color -> fresh.color == color end)
      assert texts(html, ".viewer-note") == ["#{fresh.name}・4人"]
      assert styles(html, ".avatar") |> List.first() == "background-color: #{fresh.color}"

      assert Enum.map(Chat.list_rooms(fresh.id), fn summary -> summary.room.name end) ==
               ["チーム開発", "週末の飲み会", "家族"]

      assert Chat.unread_count(team().id, fresh.id) == 0
      assert count(render(view), ".bubble--self") == 0

      sent = render_submit(view, "send", %{"body" => "ゲストからの消息"})
      assert texts(sent, ".bubble-author") |> List.last() == fresh.name
      assert count(render(view), ".bubble--self") == 1
    end

    test "creates a fresh guest for an isolated mount without a session", %{conn: _conn} do
      before = length(Chat.list_users())

      conn =
        build_conn(:get, "/rooms/room-none?room_id=room-none") |> Plug.Conn.fetch_query_params()

      assert {:error, {:redirect, %{flash: %{"error" => "ルームが見つかりません"}, to: "/"}}} =
               live_isolated(conn, LineChatWeb.RoomLive, session: %{}, router: LineChatWeb.Router)

      fresh = Chat.list_users() |> List.first()
      assert length(Chat.list_users()) == before + 1
      assert fresh.name == "ゲスト #{id_sequence(fresh.id)}"
      assert Enum.any?(@palette, fn color -> fresh.color == color end)
    end
  end

  describe "drafting and sending" do
    test "keeps the draft verbatim and hides the viewer's own typing hint", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      html = render_change(view, "update", %{"body" => "  下書き  "})

      assert attr(html, "#body", "value") == "  下書き  "
      assert texts(html, ".typing") == []
      assert Enum.any?(Chat.typing_users(team().id), fn user -> user.id == alice().id end)
      assert messages_in(team()) |> length() == 3
    end

    test "appends a sent message and clears the draft", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      html = render_submit(view, "send", %{"body" => "hello"})

      assert texts(html, ".bubble-body") ==
               ["おはよう!", "仕様を確認しました", "レビューお願いね", "hello"]

      assert texts(html, ".bubble-author") == ["アリス", "ボブ", "アリス", "アリス"]
      assert attr(html, "#body", "value") == ""
      assert texts(html, ".read-state") == ["未読", "未読", "未読"]
      assert count(html, ".bubble--self") == 3
      assert count(html, ".day-group") == 3
      assert texts(html, ".day-separator") == ["一昨日", "昨日", "今日"]
      assert Chat.unread_count(team().id, alice().id) == 0
      assert texts(render(view), ".bubble-body") |> List.last() == "hello"
    end

    test "flashes an error for a blank message", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      html = render_submit(view, "send", %{"body" => "   "})

      assert collapsed(html, ".flash--error") == ["エラー メッセージを入力してください"]
      assert texts(html, ".flash-title") == ["エラー"]
      assert texts(html, ".bubble-body") == ["おはよう!", "仕様を確認しました", "レビューお願いね"]
      assert messages_in(team()) |> length() == 3
    end

    test "flashes an error for an over-long message", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      long = String.duplicate("あ", Chat.max_body_length() + 1)
      html = render_submit(view, "send", %{"body" => long})

      assert collapsed(html, ".flash--error") ==
               ["エラー メッセージが長すぎます（最大 #{Chat.max_body_length()} 文字）"]

      assert texts(html, ".bubble-body") == ["おはよう!", "仕様を確認しました", "レビューお願いね"]
    end

    test "accepts a message at exactly the length limit", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      body = String.duplicate("あ", Chat.max_body_length())
      html = render_submit(view, "send", %{"body" => body})

      assert texts(html, ".flash--error") == []
      assert texts(html, ".bubble-body") |> List.last() == body
    end

    test "refuses a send from a viewer removed from the room", %{conn: conn} do
      guest = member_guest()
      room = create_room("退会した部屋", [guest.id, bob().id])
      {view, _html} = room_view(conn, guest.id, room)

      {:ok, _room} = Chat.remove_member(room.id, guest.id)
      html = render_submit(view, "send", %{"body" => "送れない"})

      assert collapsed(html, ".flash--error") == ["エラー このルームには参加していません"]
      assert messages_in(room) == []
      assert Chat.unread_count(room.id, guest.id) == 0
    end

    test "refuses a send once the room has left the store", %{conn: conn} do
      room = team()
      {view, _html} = room_view(conn, alice().id, room)
      :ok = Store.reset()

      html = render_submit(view, "send", %{"body" => "消えた部屋へ"})

      assert collapsed(html, ".flash--error") == ["エラー ルームが見つかりません"]
      assert {:error, :room_not_found} = Chat.list_messages(room.id)
      assert texts(html, ".bubble-body") == ["おはよう!", "仕様を確認しました", "レビューお願いね"]
    end

    test "reports a generic failure when the viewer vanishes mid-send", %{conn: conn} do
      viewer = alice()
      room = team()
      {view, _html} = room_view(conn, viewer.id, room)
      :ok = Store.reset()
      {:ok, ^room} = Store.add_room(room)

      assert {:error, :user_not_found} = Chat.fetch_user(viewer.id)
      html = render_submit(view, "send", %{"body" => "消えた人から"})

      assert collapsed(html, ".flash--error") == ["エラー メッセージを送信できません"]
      assert messages_in(room) == []
      assert texts(html, ".flash--info") == []
    end
  end

  describe "renaming the room" do
    test "trims the new name and flashes a notice", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      html = render_submit(view, "rename", %{"room_name" => "  New Name  "})

      assert texts(html, ".screen-title") == ["New Name"]
      assert attr(html, "#room_name", "value") == "New Name"
      assert collapsed(html, ".flash--info") == ["通知 ルーム名を変更しました"]
      assert texts(html, ".flash-title") == ["通知"]
      assert texts(html, ".bubble-body") == ["おはよう!", "仕様を確認しました", "レビューお願いね"]
      assert room_named("New Name").name == "New Name"
    end

    test "keeps the raw rename draft while typing", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      html = render_change(view, "rename_name", %{"room_name" => "  Draft  "})

      assert attr(html, "#room_name", "value") == "  Draft  "
      assert texts(html, ".screen-title") == ["チーム開発"]
      assert room_named("チーム開発").name == "チーム開発"
    end

    test "flashes an error for a blank rename", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      html = render_submit(view, "rename", %{"room_name" => "   "})

      assert collapsed(html, ".flash--error") == ["エラー ルーム名を入力してください"]
      assert texts(html, ".screen-title") == ["チーム開発"]
      assert attr(html, "#room_name", "value") == "チーム開発"
    end

    test "follows a rename made elsewhere", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      {:ok, _renamed} = Chat.rename_room(team().id, "リネーム済み")
      html = render(view)

      assert texts(html, ".screen-title") == ["リネーム済み"]
      assert attr(html, "#room_name", "value") == "リネーム済み"
      assert texts(html, ".viewer-note") == ["アリス・2人"]
      assert texts(html, ".bubble-body") == ["おはよう!", "仕様を確認しました", "レビューお願いね"]
    end

    test "counts a member added elsewhere", %{conn: conn} do
      {view, html} = room_view(conn, alice().id, team())
      guest = add_user("カメ")

      assert texts(html, ".viewer-note") == ["アリス・2人"]
      {:ok, _room} = Chat.add_member(team().id, guest.id)

      assert texts(render(view), ".viewer-note") == ["アリス・3人"]
      assert Chat.fetch_room(team().id) |> elem(1) |> Room.member?(guest.id)
    end

    test "reports a missing room when renaming after a reset", %{conn: conn} do
      room = team()
      {view, _html} = room_view(conn, alice().id, room)
      :ok = Store.reset()

      html = render_submit(view, "rename", %{"room_name" => "新名"})

      assert collapsed(html, ".flash--error") == ["エラー ルームが見つかりません"]
      assert texts(html, ".screen-title") == [room.name]
      assert Chat.list_all_rooms() == []
    end
  end

  describe "redacting messages" do
    test "removes the viewer's own message and notes the redaction", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      own = Enum.find(messages_in(team()), fn message -> message.author_id == alice().id end)
      html = render_click(view, "redact", %{"message" => own.id})

      assert texts(html, ".bubble-body") == ["仕様を確認しました", "レビューお願いね"]
      assert texts(html, ".redacted-note") == ["メッセージを取り消しました"]
      assert texts(html, ".bubble-author") == ["アリス", "ボブ", "アリス"]
      assert count(html, ".redact-button") == 1
      assert texts(html, ".read-state") == ["未読", "未読"]
    end

    test "refuses to redact another author's message", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      theirs = Enum.find(messages_in(team()), fn message -> message.author_id == bob().id end)
      html = render_click(view, "redact", %{"message" => theirs.id})

      assert collapsed(html, ".flash--error") == ["エラー 取り消すことができません"]
      assert texts(html, ".bubble-body") == ["おはよう!", "仕様を確認しました", "レビューお願いね"]
    end

    test "refuses to redact a message that does not exist", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      html = render_click(view, "redact", %{"message" => "m-none"})

      assert collapsed(html, ".flash--error") == ["エラー 取り消すことができません"]
      assert count(html, ".redact-button") == 2
    end

    test "refuses to redact the same message twice", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      own = Enum.find(messages_in(team()), fn message -> message.author_id == alice().id end)

      first = render_click(view, "redact", %{"message" => own.id})
      second = render_click(view, "redact", %{"message" => own.id})

      assert texts(first, ".redacted-note") == ["メッセージを取り消しました"]
      assert collapsed(second, ".flash--error") == ["エラー 取り消すことができません"]
      assert texts(second, ".redacted-note") == ["メッセージを取り消しました"]
    end

    test "follows a redaction made elsewhere", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      theirs = Enum.find(messages_in(team()), fn message -> message.author_id == bob().id end)
      {:ok, _redacted} = Chat.redact_message(theirs.id, bob().id)
      html = render(view)

      assert texts(html, ".bubble-body") == ["おはよう!", "レビューお願いね"]
      assert texts(html, ".redacted-note") == ["メッセージを取り消しました"]
      assert count(html, ".redact-button") == 2
    end
  end

  describe "live updates over the room topic" do
    test "appends a message written by another member", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      {:ok, _message} = Chat.send_message(team().id, bob().id, "ボブの追記")
      html = render(view)

      assert texts(html, ".bubble-body") ==
               ["おはよう!", "仕様を確認しました", "レビューお願いね", "ボブの追記"]

      assert texts(html, ".bubble-author") |> List.last() == "ボブ"
      assert texts(html, ".read-state") == ["未読", "未読"]
      assert texts(html, ".typing") == []
      assert Chat.unread_count(team().id, alice().id) == 1
    end

    test "names everyone typing except the viewer", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      {:ok, _typing} = Chat.set_typing(team().id, bob().id)

      assert texts(render(view), ".typing") == ["ボブが入力中…"]

      guest = member_guest()
      {:ok, _typing} = Chat.set_typing(team().id, guest.id)
      assert texts(render(view), ".typing") == ["ボブが入力中…、#{guest.name}が入力中…"]
    end

    test "keeps typing names until the ttl expires", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      {:ok, _typing} = Chat.set_typing(team().id, bob().id)
      send(view.pid, :typing_expired)

      assert texts(render(view), ".typing") == ["ボブが入力中…"]
    end

    test "leaves when the room is deleted elsewhere", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      pid = view.pid
      ref = Process.monitor(pid)
      {:ok, _deleted} = Chat.delete_room(team().id)

      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, {:redirect, opts}}}, 1000
      assert opts.status == 302
      assert opts.to == "/"
      assert decode_flash(opts.flash) == %{"error" => "ルームが削除されました"}
    end

    test "ignores broadcasts this room does not handle", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())

      for message <- [
            {:other, :x},
            {:line_chat, :nonsense, :payload},
            {:line_chat, :rooms_changed, :payload},
            {:line_chat, :user_added, :payload}
          ] do
        send(view.pid, message)
        html = render(view)
        assert is_binary(html), "broadcast #{inspect(message)} broke the view"

        assert count(html, ".bubble-body") == 3,
               "broadcast #{inspect(message)} changed the transcript"

        assert texts(html, ".viewer-note") == ["アリス・2人"]
      end
    end
  end

  describe "an empty room" do
    test "shows only the empty note", %{conn: conn} do
      guest = member_guest()
      empty = create_room("空の部屋", [guest.id])
      {_view, html} = room_view(conn, guest.id, empty)

      assert texts(html, ".screen-title") == ["空の部屋"]
      assert texts(html, ".empty-note") == ["メッセージはまだありません"]
      assert texts(html, ".viewer-note") == ["#{guest.name}・1人"]
      assert count(html, ".day-group") == 0
      assert count(html, ".bubble") == 0
      assert count(html, ".avatar") == 1
      assert styles(html, ".avatar") == ["background-color: #{guest.color}"]
      assert attr(html, ".back-link", "href") == "/"
      assert attr(html, "#room_name", "value") == "空の部屋"
    end

    test "fills the transcript and groups new days", %{conn: conn} do
      guest = member_guest()
      other = add_user("カメ")
      empty = create_room("空の部屋", [guest.id, other.id])
      append_message(empty, other, "昨日の一行", DateTime.add(DateTime.utc_now(), -@day, :second))
      append_message(empty, guest, "今日の一行")
      {_view, html} = room_view(conn, guest.id, empty)

      assert count(html, ".day-group") == 2
      assert texts(html, ".day-separator") == ["昨日", "今日"]
      assert texts(html, ".bubble-body") == ["昨日の一行", "今日の一行"]
      assert texts(html, ".empty-note") == []
    end

    test "labels an older day with its date and weekday", %{conn: conn} do
      guest = member_guest()
      other = add_user("カメ")
      empty = create_room("空の部屋", [guest.id, other.id])
      old = DateTime.add(DateTime.utc_now(), -4 * @day, :second)
      append_message(empty, other, "遥か昔の一行", old)
      {_view, html} = room_view(conn, guest.id, empty)
      label = Time.date_label(Time.local_date(old), Time.local_date(DateTime.utc_now()))

      assert texts(html, ".day-separator") == [label]
      assert label =~ ~r/^\d{1,2}月\d{1,2}日 \([月火水木金土日]\)$/u
      assert texts(html, ".bubble-time") == [Time.time_label(old)]
    end

    test "shows 不明 for an author the store does not know", %{conn: conn} do
      {view, _html} = room_view(conn, alice().id, team())
      ghost = User.new("u-ghost", "ghost")
      append_message(team(), ghost, "本文", DateTime.add(DateTime.utc_now(), -60, :second))
      html = render(view)

      assert texts(html, ".bubble-author") == ["アリス", "ボブ", "アリス", "不明"]
      assert texts(html, ".bubble-body") |> List.last() == "本文"
      assert styles(html, ".avatar") |> List.last() == "background-color: #{@default_color}"
      assert count(html, ".bubble--self") == 2
      assert count(html, ".redact-button") == 2
      assert texts(html, ".read-state") == ["未読", "未読"]
    end
  end

  describe "a room removed from the store" do
    test "does not show stale messages after reset", %{conn: conn} do
      room = team()
      alice_id = alice().id
      {_view, html} = room_view(conn, alice_id, room)
      assert texts(html, ".bubble-body") |> Enum.count() == 3

      :ok = Store.reset()

      assert {:error, {:redirect, %{flash: %{"error" => "ルームが見つかりません"}, to: "/"}}} =
               live(sess(conn, alice_id), ~p"/rooms/#{room.id}")
    end
  end
end
