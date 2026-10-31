defmodule LineChatWeb.HomeLive do
  @moduledoc """
  The room list, LINE style: unread badges, typing hints, a create-room form
  and per-room delete. Live updates arrive over PubSub.
  """

  use LineChatWeb, :live_view

  alias LineChat.Chat
  alias LineChatWeb.GuestPlug

  @room_events [
    :user_added,
    :room_deleted,
    :room_updated,
    :typing_changed,
    :read_marked,
    :message_redacted,
    :message_created
  ]

  @impl true
  def mount(_params, session, socket) do
    viewer = resolve_viewer(session)

    socket =
      socket
      |> assign(
        viewer_id: viewer.id,
        viewer: viewer,
        draft: "",
        subscriptions: MapSet.new(),
        page_title: "ルーム一覧"
      )
      |> refresh_rooms()

    if connected?(socket) do
      Chat.subscribe_rooms()
      {:ok, subscribe_rows(socket)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("check_name", %{"room_name" => name}, socket) do
    {:noreply, assign(socket, draft: name)}
  end

  @impl true
  def handle_event("create_room", %{"room_name" => name}, socket) do
    case Chat.create_room(name, member_ids()) do
      {:ok, room} ->
        {:noreply,
         socket
         |> assign(draft: "")
         |> push_navigate(to: ~p"/rooms/#{room.id}")}

      {:error, :invalid_name} ->
        {:noreply, flash_error(socket, "ルーム名を入力してください")}

      {:error, :invalid_members} ->
        {:noreply, flash_error(socket, "メンバーがいません")}
    end
  end

  @impl true
  def handle_event("delete_room", %{"room" => room_id}, socket) do
    case Chat.delete_room(room_id) do
      {:ok, _room_id} -> {:noreply, socket |> assign(draft: "") |> refresh_rooms()}
      {:error, :room_not_found} -> {:noreply, flash_error(socket, "ルームが見つかりません")}
    end
  end

  @impl true
  def handle_info({:line_chat, :rooms_changed}, socket) do
    {:noreply, socket |> refresh_rooms() |> subscribe_rows()}
  end

  @impl true
  def handle_info({:line_chat, event, _payload}, socket)
      when event in @room_events do
    {:noreply, socket |> refresh_rooms() |> subscribe_rows()}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <section class="screen">
      <header class="screen-header">
        <.avatar user={@viewer} />
        <div class="header-text">
          <h1 class="screen-title">{@page_title}</h1>
          <p class="viewer-note">{@viewer.name}</p>
        </div>
      </header>

      <form class="room-form" phx-change="check_name" phx-submit="create_room">
        <label class="field-label" for="room_name">新しいルーム</label>
        <input
          type="text"
          id="room_name"
          name="room_name"
          value={@draft}
          autocomplete="off"
          placeholder="ルーム名"
        />
        <button type="submit" class="primary-button">作成</button>
      </form>

      <ul class="room-list">
        <.room_row
          :for={row <- @rooms}
          summary={row.summary}
          href={row.href}
          typing_names={row.typing_names}
        />
      </ul>
      <p :if={@rooms == []} class="empty-note">ルームがありません</p>
    </section>
    """
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

  defp member_ids do
    Chat.list_users() |> Enum.map(& &1.id)
  end

  defp refresh_rooms(socket) do
    names = Map.new(Chat.list_users(), fn user -> {user.id, user.name} end)
    viewer_id = socket.assigns.viewer_id

    rows =
      Chat.list_rooms(viewer_id)
      |> Enum.map(fn summary ->
        %{
          summary: summary,
          typing_names: typing_names(summary.typing_user_ids, names, viewer_id),
          href: ~p"/rooms/#{summary.room.id}"
        }
      end)

    assign(socket, rooms: rows)
  end

  defp typing_names(user_ids, names, viewer_id) do
    user_ids
    |> Enum.reject(&(&1 == viewer_id))
    |> Enum.map(fn user_id -> Map.get(names, user_id, "ゲスト") end)
  end

  defp subscribe_rows(socket) do
    Enum.reduce(socket.assigns.rooms, socket, fn row, acc ->
      room_id = row.summary.room.id

      if MapSet.member?(acc.assigns.subscriptions, room_id) do
        acc
      else
        Chat.subscribe(room_id)
        assign(acc, subscriptions: MapSet.put(acc.assigns.subscriptions, room_id))
      end
    end)
  end

  defp flash_error(socket, message) do
    put_flash(socket, :error, message)
  end
end
