defmodule LineChatWeb.ChatComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import LineChatWeb.ChatComponents

  alias LineChat.Chat.{Message, Room, RoomSummary, User}
  alias LineChatWeb.ChatComponents

  @color "#67b9e8"
  @default_color "#06c755"
  @at ~U[2026-11-01 03:00:00Z]

  # Guarded clauses reject wrongly typed arguments, so dispatch dynamically.
  defp call(module, function, args), do: apply(module, function, args)

  defp alice(name \\ "アリス"), do: User.new("u-1", name, @color)
  defp bob(name \\ "ボブ"), do: User.new("u-2", name, "#f5b942")

  defp message(body \\ "こんにちは", author \\ alice()) do
    Message.new("m-1", "room-1", author.id, body, @at)
  end

  defp summary(opts \\ []) do
    room = Room.new("room-1", Keyword.get(opts, :name, "チーム開発"), [alice().id], @at)
    last = Keyword.get(opts, :last_message, message())
    unread = Keyword.get(opts, :unread, 0)
    typing = Keyword.get(opts, :typing, [])

    RoomSummary.new(room, alice().id, last, unread, typing)
  end

  defp find(html, selector) do
    {:ok, document} = Floki.parse_document(html)
    Floki.find(document, selector)
  end

  defp text(html, selector) do
    html
    |> find(selector)
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  describe "avatar/1" do
    test "renders the user color and first character" do
      html = render_component(&ChatComponents.avatar/1, %{user: alice()})

      assert text(html, ".avatar") == "ア"
      assert html =~ ~s(class="avatar")
      assert html =~ ~s(style="background-color: #67b9e8")
    end

    test "uses the default color when the user has none" do
      html = render_component(&ChatComponents.avatar/1, %{user: %User{id: "u-3", name: "カズ"}})

      assert html =~ ~s(style="background-color: #{@default_color}")
      assert text(html, ".avatar") == "カ"
    end

    test "shows a placeholder for an empty name" do
      html = render_component(&ChatComponents.avatar/1, %{user: User.new("u-4", "")})

      assert text(html, ".avatar") == "?"
    end

    test "avatar_color/1 copies a binary color and falls back otherwise" do
      assert ChatComponents.avatar_color(alice()) == @color

      assert ChatComponents.avatar_color(%User{id: "u-5", name: "ナオ", color: nil}) ==
               @default_color

      assert ChatComponents.avatar_color(%User{id: "u-6", name: "ヒデ", color: :blue}) ==
               @default_color

      assert ChatComponents.avatar_color(nil) == @default_color
    end

    test "avatar_char/1 only accepts a user struct" do
      assert ChatComponents.avatar_char(alice()) == "ア"
      assert ChatComponents.avatar_char(bob("カルロス")) == "カ"

      assert_raise FunctionClauseError, fn ->
        call(ChatComponents, :avatar_char, [nil])
      end

      assert_raise FunctionClauseError, fn ->
        call(ChatComponents, :avatar_char, ["アリス"])
      end
    end
  end

  describe "bubble/1" do
    test "marks the viewer's own message and shows 既読" do
      html =
        render_component(&ChatComponents.bubble/1, %{
          author: alice(),
          message: message(),
          self: true,
          read_state: :read,
          time: "12:00"
        })

      assert html =~ ~s(class="bubble bubble--self")
      assert text(html, ".bubble-author") == "アリス"
      assert text(html, ".bubble-body") == "こんにちは"
      assert text(html, ".bubble-time") == "12:00"
      assert text(html, ".read-state") == "既読"
    end

    test "shows 未読 for an unread own message" do
      html =
        render_component(&ChatComponents.bubble/1, %{
          author: alice(),
          message: message(),
          self: true,
          read_state: :unread
        })

      assert text(html, ".read-state") == "未読"
    end

    test "omits the read state when none is given" do
      html =
        render_component(&ChatComponents.bubble/1, %{
          author: alice(),
          message: message(),
          self: true
        })

      assert find(html, ".read-state") == []
      assert text(html, ".bubble-time") == ""
    end

    test "renders someone else's message without a redact button" do
      html =
        render_component(&ChatComponents.bubble/1, %{
          author: bob(),
          message: message("どうぞ", bob())
        })

      assert html =~ ~s(class="bubble")
      refute html =~ "bubble--self"
      assert text(html, ".bubble-author") == "ボブ"
      assert find(html, ".read-state") == []
      assert find(html, ".redact-button") == []
    end

    test "replaces a redacted body with the redacted note" do
      html =
        render_component(&ChatComponents.bubble/1, %{
          author: alice(),
          message: Message.redact(message()),
          self: true,
          read_state: :read
        })

      assert text(html, ".redacted-note") == "メッセージを取り消しました"
      assert find(html, ".bubble-body") == []
      assert find(html, ".redact-button") == []
    end

    test "offers a redact button carrying the message id" do
      html =
        render_component(&ChatComponents.bubble/1, %{
          author: alice(),
          message: message(),
          self: true
        })

      assert text(html, ".redact-button") == "取り消す"
      assert html =~ ~s(phx-click="redact")
      assert html =~ ~s(phx-value-message="m-1")
    end

    test "bubble_class/1 distinguishes the viewer" do
      assert ChatComponents.bubble_class(true) == "bubble bubble--self"
      assert ChatComponents.bubble_class(false) == "bubble"
      assert ChatComponents.bubble_class(nil) == "bubble"
    end
  end

  describe "day_separator/1" do
    test "renders the label inside the separator" do
      html = render_component(&ChatComponents.day_separator/1, %{label: "今日"})

      assert html =~ ~s(class="day-separator")
      assert text(html, ".day-separator") == "今日"
    end
  end

  describe "room_row/1" do
    test "links into the room with name and preview" do
      html =
        render_component(&ChatComponents.room_row/1, %{summary: summary(), href: "/rooms/room-1"})

      assert html =~ ~s(href="/rooms/room-1")
      assert text(html, ".room-name") == "チーム開発"
      assert text(html, ".room-preview") == "こんにちは"
      assert text(html, ".room-avatar") == "チ"
    end

    test "shows a glyph for an unnamed room" do
      html =
        render_component(&ChatComponents.room_row/1, %{
          summary: summary(name: ""),
          href: "/rooms/room-1"
        })

      assert text(html, ".room-avatar") == "G"
    end

    test "badges unread messages" do
      html =
        render_component(&ChatComponents.room_row/1, %{
          summary: summary(unread: 3),
          href: "/rooms/room-1"
        })

      assert text(html, ".unread-badge") == "3"
    end

    test "omits the badge when nothing is unread" do
      html =
        render_component(&ChatComponents.room_row/1, %{
          summary: summary(unread: 0),
          href: "/rooms/room-1"
        })

      assert find(html, ".unread-badge") == []
    end

    test "keeps the delete button outside the link" do
      html =
        render_component(&ChatComponents.room_row/1, %{summary: summary(), href: "/rooms/room-1"})

      assert find(html, ".room-row-link .delete-room") == []
      assert text(html, ".delete-room") == "削除"
      assert html =~ ~s(phx-click="delete_room")
      assert html =~ ~s(phx-value-room="room-1")
    end

    test "shows no typing hint when nobody is typing" do
      html =
        render_component(&ChatComponents.room_row/1, %{summary: summary(), href: "/rooms/room-1"})

      assert find(html, ".typing") == []
    end

    test "shows typing hints passed from the caller" do
      html =
        render_component(&ChatComponents.room_row/1, %{
          summary: summary(),
          href: "/rooms/room-1",
          typing_names: ["ボブ", "カルロス"]
        })

      assert text(html, ".typing") == "ボブが入力中…、カルロスが入力中…"
    end

    test "previews an empty room" do
      html =
        render_component(&ChatComponents.room_row/1, %{
          summary: summary(last_message: nil),
          href: "/rooms/room-1"
        })

      assert text(html, ".room-preview") == "メッセージはまだありません"
    end

    test "previews a redacted last message" do
      html =
        render_component(&ChatComponents.room_row/1, %{
          summary: summary(last_message: Message.redact(message())),
          href: "/rooms/room-1"
        })

      assert text(html, ".room-preview") == "メッセージを取り消しました"
    end

    test "truncates a long preview" do
      long = String.duplicate("あ", 30)

      html =
        render_component(&ChatComponents.room_row/1, %{
          summary: summary(last_message: message(long)),
          href: "/rooms/room-1"
        })

      assert text(html, ".room-preview") == String.duplicate("あ", 28) <> "…"
    end
  end

  describe "typing_label/1" do
    test "returns nil when nobody is typing" do
      assert typing_label([]) == nil
    end

    test "names a single typist" do
      assert typing_label(["ボブ"]) == "ボブが入力中…"
    end

    test "joins several typists" do
      assert typing_label(["ボブ", "カルロス"]) == "ボブが入力中…、カルロスが入力中…"
    end
  end

  describe "flash_group/1" do
    test "renders an info flash with its title" do
      html =
        render_component(&ChatComponents.flash_group/1, %{
          flash: %{"info" => "ルーム名を変更しました"}
        })

      assert html =~ ~s(id="flash_group")
      assert text(html, ".flash") == "通知 ルーム名を変更しました"
      assert html =~ ~s(class="flash flash--info")
      assert text(html, ".flash-title") == "通知"
      assert html =~ ~s(phx-click="lv:clear-flash")
      assert html =~ ~s(phx-value-key="info")
    end

    test "renders an error flash with its title" do
      html =
        render_component(&ChatComponents.flash_group/1, %{
          flash: %{"error" => "メッセージを入力してください"}
        })

      assert html =~ ~s(class="flash flash--error")
      assert text(html, ".flash") == "エラー メッセージを入力してください"
      assert text(html, ".flash-title") == "エラー"
      assert html =~ ~s(phx-value-key="error")
    end

    test "renders both kinds when both are present" do
      html =
        render_component(&ChatComponents.flash_group/1, %{
          flash: %{"info" => "通知です", "error" => "失敗しました"}
        })

      assert length(find(html, ".flash")) == 2
      assert text(html, ".flash--info") == "通知 通知です"
      assert text(html, ".flash--error") == "エラー 失敗しました"
    end

    test "renders nothing when no flash is set" do
      html = render_component(&ChatComponents.flash_group/1, %{flash: %{}})

      assert find(html, ".flash") == []
      assert html =~ ~s(id="flash_group")
    end

    test "flash/1 skips the title when none is passed" do
      html =
        render_component(&ChatComponents.flash/1, %{
          kind: :info,
          flash: %{"info" => "ただいま"}
        })

      assert find(html, ".flash-title") == []
      assert text(html, ".flash") == "ただいま"
    end

    test "flash/1 skips a key that is not set" do
      html =
        render_component(&ChatComponents.flash/1, %{
          kind: :error,
          flash: %{"info" => "ただいま"}
        })

      assert find(html, ".flash") == []
    end
  end
end
