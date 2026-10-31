defmodule LineChat.Chat.Message do
  @moduledoc """
  A single chat message. Redacted messages render as LINE's struck-through
  "message deleted" bubble.
  """

  defstruct [:id, :room_id, :author_id, :body, :inserted_at, redacted: false]

  @type t :: %__MODULE__{
          id: String.t(),
          room_id: String.t(),
          author_id: String.t(),
          body: String.t(),
          inserted_at: DateTime.t(),
          redacted: boolean()
        }

  @doc """
  Builds a message from already validated input.
  """
  def new(id, room_id, author_id, body, inserted_at)
      when is_binary(id) and is_binary(room_id) and is_binary(author_id) and is_binary(body) do
    %__MODULE__{
      id: id,
      room_id: room_id,
      author_id: author_id,
      body: body,
      inserted_at: inserted_at,
      redacted: false
    }
  end

  @doc """
  Marks a message as redacted. The stored body is preserved but never displayed.
  """
  def redact(%__MODULE__{} = message), do: %{message | redacted: true}

  @doc """
  Returns true once the message has been redacted by its author.
  """
  def redacted?(%__MODULE__{redacted: redacted}), do: redacted

  @doc """
  The text shown in the bubble: empty for redacted messages.
  """
  def displayed_body(%__MODULE__{redacted: true}), do: ""
  def displayed_body(%__MODULE__{body: body}), do: body
end
