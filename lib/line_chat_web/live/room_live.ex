defmodule LineChatWeb.RoomLive do
  @moduledoc """
  One room's transcript, LINE style: day separators, bubbles with read
  receipts, a typing hint, renaming, redacting and sending. Live updates arrive
  over the room's PubSub topic.
  """

  use LineChatWeb, :live_view

  alias LineChat.Chat
  alias LineChat.Chat.{Room, Time, User}
  alias LineChatWeb.GuestPlug

  @typing_refresh_ms 4_500
  @transcript_events [:message_created, :message_redacted, :read_marked, :typing_changed]
  @unknown_name "不明"

  @impl true
  def mount(params, session, socket) do
    viewer = resolve_viewer(session)

    case Chat.fetch_room(params["room_id"]) do
      {:ok, room} ->
        if Room.member?(room, viewer.id) do
          init_socket(socket, viewer, room)
        else
          {:ok, leave_room(socket, "このルームには参加していません")}
        end

      {:error, _reason} ->
        {:ok, leave_room(socket, "ルームが見つかりません")}
    end
  end

  @impl true
  def handle_event("update", %{"body" => body}, socket) do
    Chat.set_typing(socket.assigns.room.id, socket.assigns.viewer_id)
    {:noreply, assign(socket, draft: body)}
  end

  @impl true
  def handle_event("send", %{"body" => body}, socket) do
    case Chat.send_message(socket.assigns.room.id, socket.assigns.viewer_id, body) do
      {:ok, _message} -> {:noreply, socket |> assign(draft: "") |> refresh_transcript()}
      {:error, reason} -> {:noreply, flash_error(socket, send_error(reason))}
    end
  end

  @impl true
  def handle_event("redact", %{"message" => message_id}, socket) do
    case Chat.redact_message(message_id, socket.assigns.viewer_id) do
      {:ok, _message} -> {:noreply, socket |> refresh_transcript()}
      {:error, _reason} -> {:noreply, flash_error(socket, "取り消すことができません")}
    end
  end

  @impl true
  def handle_event("rename_name", %{"room_name" => name}, socket) do
    {:noreply, assign(socket, name_draft: name)}
  end

  @impl true
  def handle_event("rename", %{"room_name" => name}, socket) do
    case Chat.rename_room(socket.assigns.room.id, name) do
      {:ok, room} ->
        {:noreply,
         socket
         |> assign(room: room, page_title: room.name, name_draft: room.name)
         |> flash_info("ルーム名を変更しました")
         |> refresh_transcript()}

      {:error, :invalid_name} ->
        {:noreply, flash_error(socket, "ルーム名を入力してください")}

      {:error, :room_not_found} ->
        {:noreply, flash_error(socket, "ルームが見つかりません")}
    end
  end

  @impl true
  def handle_info({:line_chat, :room_deleted, _room_id}, socket) do
    {:noreply, leave_room(socket, "ルームが削除されました")}
  end

  @impl true
  def handle_info({:line_chat, :room_updated, %Room{} = room}, socket) do
    {:noreply,
     socket
     |> assign(room: room, page_title: room.name, name_draft: room.name)
     |> refresh_transcript()}
  end

  @impl true
  def handle_info({:line_chat, event, _payload}, socket) when event in @transcript_events do
    {:noreply, socket |> refresh_transcript() |> schedule_typing_refresh()}
  end

  @impl true
  def handle_info(:typing_expired, socket) do
    {:noreply, socket |> refresh_transcript() |> schedule_typing_refresh()}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <section class="screen screen--room">
      <a class="back-link" href={~p"/"}>戻る</a>

      <header class="screen-header">
        <.avatar user={@viewer} />
        <div class="header-text">
          <h1 class="screen-title">{@page_title}</h1>
          <p class="viewer-note">{@viewer.name}・{@room.member_ids |> length()}人</p>
        </div>
      </header>

      <form class="rename-form" phx-change="rename_name" phx-submit="rename">
        <label class="field-label" for="room_name">ルーム名</label>
        <input
          type="text"
          id="room_name"
          name="room_name"
          value={@name_draft}
          autocomplete="off"
        />
        <button type="submit" class="ghost-button">変更</button>
      </form>

      <p :if={@typing_names != []} class="typing">{typing_label(@typing_names)}</p>

      <div class="transcript">
        <div :for={group <- @groups} class="day-group">
          <.day_separator label={group.label} />
          <.bubble
            :for={row <- group.rows}
            message={row.message}
            author={row.author}
            self={row.self}
            read_state={row.read_state}
            time={row.time}
          />
        </div>
        <p :if={@groups == []} class="empty-note">メッセージはまだありません</p>
      </div>

      <form class="send-form" phx-change="update" phx-submit="send">
        <label class="field-label" for="body">メッセージ</label>
        <input
          type="text"
          id="body"
          name="body"
          value={@draft}
          autocomplete="off"
          placeholder="メッセージを入力"
        />
        <button type="submit" class="primary-button">送信</button>
      </form>
    </section>
    """
  end

  defp init_socket(socket, viewer, room) do
    socket =
      socket
      |> assign(
        viewer_id: viewer.id,
        viewer: viewer,
        room: room,
        draft: "",
        name_draft: room.name,
        page_title: room.name
      )
      |> refresh_transcript()

    if connected?(socket) do
      Chat.subscribe(room.id)
      Chat.mark_read(room.id, viewer.id)
      {:ok, socket |> refresh_transcript() |> schedule_typing_refresh()}
    else
      {:ok, socket}
    end
  end

  defp refresh_transcript(socket) do
    viewer_id = socket.assigns.viewer_id
    room_id = socket.assigns.room.id
    {:ok, messages} = Chat.list_messages(room_id)

    authors = Map.new(Chat.list_users(), fn user -> {user.id, user} end)
    statuses = Chat.read_statuses(room_id, viewer_id)

    groups =
      Chat.group_by_day(messages, DateTime.utc_now())
      |> Enum.map(fn group ->
        %{
          date: group.date,
          label: group.label,
          rows: Enum.map(group.messages, &row(&1, authors, statuses, viewer_id))
        }
      end)

    assign(socket,
      groups: groups,
      typing_names: typing_names(Chat.typing_users(room_id), viewer_id)
    )
  end

  defp row(message, authors, statuses, viewer_id) do
    %{
      message: message,
      author: Map.get(authors, message.author_id, User.new(message.author_id, @unknown_name)),
      self: message.author_id == viewer_id,
      read_state: Map.get(statuses, message.id),
      time: Time.time_label(message.inserted_at)
    }
  end

  defp typing_names(users, viewer_id) do
    users
    |> Enum.reject(&(&1.id == viewer_id))
    |> Enum.map(& &1.name)
  end

  defp schedule_typing_refresh(socket) do
    Process.send_after(self(), :typing_expired, @typing_refresh_ms)
    socket
  end

  defp leave_room(socket, message) do
    socket
    |> flash_error(message)
    |> redirect(to: ~p"/")
  end

  defp resolve_viewer(session) do
    case session[GuestPlug.session_key()] do
      guest_id when is_binary(guest_id) ->
        case Chat.fetch_user(guest_id) do
          {:ok, viewer} -> viewer
          {:error, _reason} -> create_guest()
        end

      _missing ->
        create_guest()
    end
  end

  defp create_guest do
    {:ok, viewer} = Chat.create_guest_user()
    viewer
  end

  defp send_error(:invalid_body), do: "メッセージを入力してください"
  defp send_error(:too_long), do: "メッセージが長すぎます（最大 #{Chat.max_body_length()} 文字）"
  defp send_error(:not_a_member), do: "このルームには参加していません"
  defp send_error(:room_not_found), do: "ルームが見つかりません"
  defp send_error(_other), do: "メッセージを送信できません"

  defp flash_error(socket, message) do
    put_flash(socket, :error, message)
  end

  defp flash_info(socket, message) do
    put_flash(socket, :info, message)
  end
end
