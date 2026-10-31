defmodule LineChatWeb.HomeLiveTest do
  use LineChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import LineChat.ChatCase

  alias LineChat.Chat
  alias LineChat.Chat.Store
  alias LineChatWeb.GuestPlug

  @palette ["#06c755", "#67b9e8", "#f5b942", "#e77fb2", "#9a8ad6", "#59c1c0"]
  @alice_color "#67b9e8"
  @bob_color "#f5b942"
  @empty_preview "メッセージはまだありません"

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

  defp avatar_style(html) do
    styles(html, ".avatar") |> List.first()
  end

  defp hrefs(html) do
    html
    |> find(".room-row-link")
    |> Enum.map(fn node -> Floki.attribute(node, "href") |> List.first() end)
  end

  defp named(name) do
    Enum.find(Chat.list_users(), fn user -> user.name == name end)
  end

  defp room_named(name) do
    Enum.find(Chat.list_all_rooms(), fn room -> room.name == name end)
  end

  defp member_guest(conn) do
    {:ok, guest} = Chat.create_guest_user()
    {:ok, view, html} = live(sess(conn, guest.id), ~p"/")
    {guest, view, html}
  end

  defp from_session(conn, user_id) do
    {:ok, view, html} = live(sess(conn, user_id), ~p"/")
    {view, html}
  end

  describe "mounting the room list" do
    test "shows every seeded room for a brand new guest", %{conn: conn} do
      {_guest, _view, html} = member_guest(conn)

      assert texts(html, ".screen-title") == ["ルーム一覧"]
      assert texts(html, ".room-name") == ["チーム開発", "週末の飲み会", "家族"]
      assert texts(html, ".room-preview") == ["レビューお願いね", "幹事任せるね", "ただいま"]
      assert texts(html, ".unread-badge") == ["3", "2", "1"]
      assert texts(html, ".room-avatar") == ["チ", "週", "家"]
      assert count(html, ".room-row") == 3
      assert texts(html, ".typing") == []
      assert texts(html, ".empty-note") == []
    end

    test "names the new guest after its id and uses a palette colour", %{conn: conn} do
      {guest, _view, html} = member_guest(conn)

      assert texts(html, ".viewer-note") == [guest.name]
      assert String.starts_with?(guest.name, "ゲスト ")
      assert guest.name == "ゲスト #{id_sequence(guest.id)}"
      assert Enum.any?(@palette, fn color -> guest.color == color end)
      assert avatar_style(html) == "background-color: #{guest.color}"
      assert texts(html, ".avatar") |> Enum.at(0) == "ゲ"
    end

    test "keeps a known session identity", %{conn: conn} do
      alice = named("アリス")
      {view, html} = from_session(conn, alice.id)

      assert texts(html, ".viewer-note") == ["アリス"]
      assert avatar_style(html) == "background-color: #{@alice_color}"
      assert texts(html, ".unread-badge") == []
      assert count(html, ".room-row") == 3
      assert attr(render(view), "#room_name", "value") == ""
    end

    test "shows bob's avatar colour for the second seeded member", %{conn: conn} do
      # The home screen renders only the viewer's avatar, so bob's colour is
      # visible when the session resolves to bob.
      {_view, html} = from_session(conn, named("ボブ").id)

      assert texts(html, ".viewer-note") == ["ボブ"]
      assert count(html, ".avatar") == 1
      assert avatar_style(html) == "background-color: #{@bob_color}"
      assert texts(html, ".unread-badge") == ["2", "1", "1"]
    end

    test "replaces an unknown session id with a fresh guest", %{conn: conn} do
      {view, html} = from_session(conn, "u-deleted")

      assert {:error, :user_not_found} = Chat.fetch_user("u-deleted")
      assert texts(html, ".viewer-note") |> Enum.at(0) |> String.starts_with?("ゲスト ")
      assert count(html, ".room-row") == 3
      assert attr(render(view), "#room_name", "placeholder") == "ルーム名"
    end

    test "links each row to its room", %{conn: conn} do
      {_guest, _view, html} = member_guest(conn)
      team = room_named("チーム開発")
      party = room_named("週末の飲み会")
      family = room_named("家族")

      expected =
        Enum.map([team, party, family], fn room -> ~p"/rooms/#{room.id}" |> to_string() end)

      assert hrefs(html) == expected
      assert find(html, ".back-link") == []
    end

    test "renders without a socket for a disconnected GET", %{conn: conn} do
      alice = named("アリス")
      html = sess(conn, alice.id) |> get(~p"/") |> html_response(200)

      assert texts(html, ".screen-title") == ["ルーム一覧"]
      assert texts(html, ".viewer-note") == ["アリス"]
      assert count(html, ".room-row") == 3
      assert texts(html, ".unread-badge") == []
    end

    test "does not mark the disconnected viewer's rooms as read", %{conn: conn} do
      {:ok, guest} = Chat.create_guest_user()
      Chat.mark_read(room_named("チーム開発").id, named("ボブ").id)

      html = sess(conn, guest.id) |> get(~p"/") |> html_response(200)

      assert texts(html, ".unread-badge") == ["3", "2", "1"]
      assert Chat.unread_count(room_named("チーム開発").id, guest.id) == 3
    end

    test "creates a fresh guest when the session carries no viewer", %{conn: conn} do
      known_ids = Enum.map(Chat.list_users(), fn user -> user.id end)
      {:ok, _view, html} = live_isolated(conn, LineChatWeb.HomeLive, session: %{})

      [viewer_name] = texts(html, ".viewer-note")
      fresh = Enum.find(Chat.list_users(), fn user -> user.name == viewer_name end)

      assert fresh.name == "ゲスト #{id_sequence(fresh.id)}"
      refute fresh.id in known_ids
      assert Enum.any?(@palette, fn color -> fresh.color == color end)
      assert count(html, ".room-row") == 3
    end
  end

  describe "creating a room" do
    test "pushes a navigation to the freshly created room", %{conn: conn} do
      {guest, view, _html} = member_guest(conn)

      assert {:error, {:live_redirect, %{kind: :push, to: to}}} =
               render_submit(view, "create_room", %{"room_name" => " New Room "})

      assert to == "/rooms/" <> trimmed_id(to)
      {:ok, room} = Chat.fetch_room(String.replace(to, "/rooms/", ""))
      assert room.name == "New Room"
      assert guest.id in room.member_ids

      assert Enum.sort(room.member_ids) ==
               Enum.sort(Enum.map(Chat.list_users(), fn u -> u.id end))
    end

    test "lists the new room first with an empty preview", %{conn: conn} do
      {guest, view, _html} = member_guest(conn)

      {:error, {:live_redirect, %{to: _to}}} =
        render_submit(view, "create_room", %{"room_name" => "新ルーム"})

      {_view, html} = from_session(conn, guest.id)

      assert texts(html, ".room-name") == ["新ルーム", "チーム開発", "週末の飲み会", "家族"]
      assert texts(html, ".room-preview") == [@empty_preview, "レビューお願いね", "幹事任せるね", "ただいま"]
      assert texts(html, ".unread-badge") == ["3", "2", "1"]
      assert texts(html, ".room-avatar") == ["新", "チ", "週", "家"]
    end

    test "rejects a blank name and keeps the list intact", %{conn: conn} do
      {guest, view, _html} = member_guest(conn)
      html = render_submit(view, "create_room", %{"room_name" => "   "})

      assert collapsed(html, ".flash--error") == ["エラー ルーム名を入力してください"]
      assert count(html, ".room-row") == 3

      assert Chat.list_rooms(guest.id) |> Enum.map(fn summary -> summary.room.name end) ==
               ["チーム開発", "週末の飲み会", "家族"]
    end

    test "keeps the typed draft exactly as entered", %{conn: conn} do
      {_guest, view, _html} = member_guest(conn)
      html = render_change(view, "check_name", %{"room_name" => "  Draft  "})

      assert attr(html, "#room_name", "value") == "  Draft  "
      assert count(html, ".room-row") == 3
      assert Chat.list_all_rooms() |> Enum.map(fn r -> r.name end) |> length() == 3
    end

    test "overwrites the draft on every change", %{conn: conn} do
      {_guest, view, _html} = member_guest(conn)
      _first = render_change(view, "check_name", %{"room_name" => "第一"})
      html = render_change(view, "check_name", %{"room_name" => "第二"})

      assert attr(html, "#room_name", "value") == "第二"
    end

    test "rejects a create request once no members remain in the store", %{conn: conn} do
      {guest, view, _html} = member_guest(conn)
      :ok = Store.reset()

      html = render_submit(view, "create_room", %{"room_name" => "誰もいない"})

      assert collapsed(html, ".flash--error") == ["エラー メンバーがいません"]
      assert texts(html, ".viewer-note") == [guest.name]
      assert Enum.all?(Chat.list_all_rooms(), fn room -> room.name != "誰もいない" end)
    end
  end

  describe "deleting a room" do
    test "drops the row and resets the draft", %{conn: conn} do
      {_guest, view, _html} = member_guest(conn)
      party = room_named("週末の飲み会")
      render_change(view, "check_name", %{"room_name" => "下書き"})

      html = render_click(view, "delete_room", %{"room" => party.id})

      assert texts(html, ".room-name") == ["チーム開発", "家族"]
      assert count(html, ".room-row") == 2
      assert texts(html, ".unread-badge") == ["3", "1"]
      assert attr(html, "#room_name", "value") == ""
      assert {:error, :room_not_found} = Chat.fetch_room(party.id)
      assert texts(html, ".flash--error") == []
    end

    test "links the surviving rooms in activity order", %{conn: conn} do
      {_guest, view, _html} = member_guest(conn)
      html = render_click(view, "delete_room", %{"room" => room_named("家族").id})
      team = room_named("チーム開発")
      party = room_named("週末の飲み会")

      assert hrefs(html) == [
               ~p"/rooms/#{team.id}" |> to_string(),
               ~p"/rooms/#{party.id}" |> to_string()
             ]
    end

    test "flashes an error for a room that is already gone", %{conn: conn} do
      {_guest, view, _html} = member_guest(conn)
      html = render_click(view, "delete_room", %{"room" => "room-nope"})

      assert collapsed(html, ".flash--error") == ["エラー ルームが見つかりません"]
      assert count(html, ".room-row") == 3
      assert texts(html, ".room-name") == ["チーム開発", "週末の飲み会", "家族"]
    end

    test "clears a flash on click", %{conn: conn} do
      {_guest, view, _html} = member_guest(conn)
      _html = render_click(view, "delete_room", %{"room" => "room-nope"})
      html = render_click(view, "lv:clear-flash", %{"key" => "error"})

      assert texts(html, ".flash--error") == []
      assert count(html, ".room-row") == 3
    end
  end

  describe "live room-list updates" do
    test "appends a room created elsewhere", %{conn: conn} do
      alice = named("アリス")
      {view, _html} = from_session(conn, alice.id)
      {:ok, room} = Chat.create_room("外部ルーム", [alice.id])
      html = render(view)

      assert texts(html, ".room-name") == ["外部ルーム", "チーム開発", "週末の飲み会", "家族"]
      assert texts(html, ".room-preview") |> Enum.at(0) == @empty_preview
      assert texts(html, ".unread-badge") == []
      assert hrefs(html) |> Enum.at(0) == "/rooms/#{room.id}"
    end

    test "reflects a message sent by another member", %{conn: conn} do
      {_guest, view, _html} = member_guest(conn)
      party = room_named("週末の飲み会")
      {:ok, _message} = Chat.send_message(party.id, named("ボブ").id, "乾杯!")
      html = render(view)

      assert texts(html, ".room-preview") == ["乾杯!", "レビューお願いね", "ただいま"]
      assert texts(html, ".unread-badge") == ["3", "3", "1"]
    end

    test "shrinks the badge when the other member reads", %{conn: conn} do
      alice = named("アリス")
      {view, _html} = from_session(conn, alice.id)
      {:ok, _message} = Chat.send_message(room_named("チーム開発").id, named("ボブ").id, "レビュー済み")
      html = render(view)

      assert texts(html, ".unread-badge") == ["1"]
      Chat.mark_read(room_named("チーム開発").id, alice.id)
      html = render(view)

      assert texts(html, ".unread-badge") == []
      assert texts(html, ".room-preview") |> Enum.at(0) == "レビュー済み"
    end

    test "shows a typing hint for another member", %{conn: conn} do
      {_guest, view, _html} = member_guest(conn)
      {:ok, _until} = Chat.set_typing(room_named("家族").id, named("アリス").id)
      html = render(view)

      assert texts(html, ".typing") == ["アリスが入力中…"]
      assert texts(html, ".room-name") == ["チーム開発", "週末の飲み会", "家族"]
    end

    test "never hints about the viewer typing in a room", %{conn: conn} do
      alice = named("アリス")
      {view, _html} = from_session(conn, alice.id)
      {:ok, _until} = Chat.set_typing(room_named("チーム開発").id, alice.id)
      html = render(view)

      assert texts(html, ".typing") == []
    end

    test "labels a typing id that is not a known user as ゲスト", %{conn: conn} do
      {_guest, view, _html} = member_guest(conn)
      {:ok, _until} = Chat.set_typing(room_named("チーム開発").id, "u-ghost")
      html = render(view)

      assert texts(html, ".typing") == ["ゲストが入力中…"]
      assert Chat.typing_users(room_named("チーム開発").id) == []
      assert texts(html, ".room-name") == ["チーム開発", "週末の飲み会", "家族"]
    end

    test "does not change room names when a ghost starts typing", %{conn: conn} do
      {_guest, _view, html} = member_guest(conn)
      {:ok, _until} = Chat.set_typing(room_named("チーム開発").id, "u-ghost")

      assert texts(html, ".room-name") == ["チーム開発", "週末の飲み会", "家族"]
      assert count(html, ".room-row") == 3
    end

    test "swaps the preview when a message is redacted", %{conn: conn} do
      {_guest, view, _html} = member_guest(conn)
      party = room_named("週末の飲み会")
      {:ok, message} = Chat.send_message(party.id, named("ボブ").id, "遅れます")
      {:ok, _redacted} = Chat.redact_message(message.id, named("ボブ").id)
      html = render(view)

      assert texts(html, ".room-preview") == ["メッセージを取り消しました", "レビューお願いね", "ただいま"]
    end

    test "renames a room created elsewhere", %{conn: conn} do
      alice = named("アリス")
      {view, _html} = from_session(conn, alice.id)
      {:ok, _room} = Chat.rename_room(room_named("チーム開発").id, "改名済み")
      html = render(view)

      assert texts(html, ".room-name") == ["改名済み", "週末の飲み会", "家族"]
      assert texts(html, ".room-avatar") == ["改", "週", "家"]
    end

    test "drops a room deleted elsewhere", %{conn: conn} do
      {_guest, view, _html} = member_guest(conn)
      {:ok, _deleted} = Chat.delete_room(room_named("家族").id)
      html = render(view)

      assert texts(html, ".room-name") == ["チーム開発", "週末の飲み会"]
      assert count(html, ".room-row") == 2
      assert texts(html, ".empty-note") == []
    end

    test "ignores unknown and mismatched broadcasts", %{conn: conn} do
      {_guest, view, _html} = member_guest(conn)
      room = room_named("チーム開発")

      for message <- [
            {:other, :x},
            {:line_chat, :nonsense, :payload},
            {:line_chat, :room_deleted, "room-nope"},
            {:line_chat, :room_updated, room},
            {:line_chat, :rooms_changed},
            :typing_expired
          ] do
        send(view.pid, message)
        html = render(view)
        assert count(html, ".room-row") == 3, "broadcast #{inspect(message)} changed the list"
      end
    end

    test "adds a user without changing the room list", %{conn: conn} do
      {guest, view, _html} = member_guest(conn)
      {:ok, _user} = Chat.add_user("新入ユーザー")
      html = render(view)

      assert count(html, ".room-row") == 3
      assert texts(html, ".viewer-note") == [guest.name]
    end

    test "subscribes newly appearing rooms so their messages arrive", %{conn: conn} do
      alice = named("アリス")
      {view, _html} = from_session(conn, alice.id)
      {:ok, room} = Chat.create_room("後から部屋", [alice.id, named("ボブ").id])
      html = render(view)

      assert count(html, ".room-row") == 4
      {:ok, _message} = Chat.send_message(room.id, named("ボブ").id, "最初のメッセージ")
      html = render(view)

      assert texts(html, ".room-preview") |> Enum.at(0) == "最初のメッセージ"
      assert texts(html, ".unread-badge") == ["1"]
    end
  end

  describe "an empty store" do
    test "shows an empty note for a disconnected GET", %{conn: conn} do
      :ok = Store.reset()

      html = sess(conn, "u-nope") |> get(~p"/") |> html_response(200)

      assert texts(html, ".empty-note") == ["ルームがありません"]
      assert count(html, ".room-row") == 0
      assert texts(html, ".unread-badge") == []
      assert texts(html, ".screen-title") == ["ルーム一覧"]
    end

    test "shows an empty note for a connected guest", %{conn: conn} do
      :ok = Store.reset()
      {guest, view, html} = member_guest(conn)

      assert texts(html, ".empty-note") == ["ルームがありません"]
      assert count(html, ".room-row") == 0
      assert texts(html, ".viewer-note") == [guest.name]
      assert attr(render(view), "#room_name", "value") == ""
    end

    test "rejects a blank name while the list stays empty", %{conn: conn} do
      :ok = Store.reset()
      {guest, view, _html} = member_guest(conn)

      html = render_submit(view, "create_room", %{"room_name" => "   "})

      assert collapsed(html, ".flash--error") == ["エラー ルーム名を入力してください"]
      assert count(html, ".room-row") == 0
      assert texts(html, ".empty-note") == ["ルームがありません"]
      assert texts(html, ".viewer-note") == [guest.name]
    end

    test "shows the first room after creating one", %{conn: conn} do
      :ok = Store.reset()
      {guest, view, _html} = member_guest(conn)

      {:error, {:live_redirect, %{to: to}}} =
        render_submit(view, "create_room", %{"room_name" => "一杯目"})

      {_view, html} = from_session(conn, guest.id)

      assert texts(html, ".room-name") == ["一杯目"]
      assert texts(html, ".empty-note") == []
      assert hrefs(html) == [to]
    end
  end

  defp trimmed_id(to) do
    String.replace(to, "/rooms/", "")
  end
end
