defmodule LineChat.Chat.TimeTest do
  use ExUnit.Case, async: true

  alias LineChat.Chat.Time

  @noon ~U[2026-10-31 03:00:00Z]
  @today ~D[2026-11-01]

  # Guard clauses reject typed literals at compile time, so wrongly typed
  # arguments are dispatched dynamically.
  defp call(module, function, args), do: apply(module, function, args)

  describe "utc_offset/0" do
    test "defaults to Japan Standard Time" do
      assert Time.utc_offset() == 9 * 3600
    end

    test "follows the configured value" do
      previous = Application.get_env(:line_chat, :utc_offset)

      try do
        Application.put_env(:line_chat, :utc_offset, 0)
        assert Time.utc_offset() == 0
      after
        if previous == nil do
          Application.delete_env(:line_chat, :utc_offset)
        else
          Application.put_env(:line_chat, :utc_offset, previous)
        end
      end
    end
  end

  describe "to_local/1" do
    test "shifts a UTC timestamp by the display offset" do
      assert Time.to_local(@noon) == ~U[2026-10-31 12:00:00Z]
    end

    test "rolls a UTC evening into the next local day" do
      assert Time.to_local(~U[2026-10-31 20:00:00Z]) == ~U[2026-11-01 05:00:00Z]
    end

    test "keeps the timezone" do
      assert %DateTime{time_zone: "Etc/UTC"} = Time.to_local(@noon)
    end

    test "rejects anything that is not a DateTime" do
      assert_raise FunctionClauseError, fn -> call(Time, :to_local, [~D[2026-10-31]]) end
      assert_raise FunctionClauseError, fn -> call(Time, :to_local, ["2026-10-31"]) end
    end
  end

  describe "local_date/1" do
    test "returns the display-timezone date" do
      assert Time.local_date(@noon) == ~D[2026-10-31]
    end

    test "crosses the date boundary at JST midnight" do
      assert Time.local_date(~U[2026-10-31 14:59:00Z]) == ~D[2026-10-31]
      assert Time.local_date(~U[2026-10-31 15:00:00Z]) == ~D[2026-11-01]
    end

    test "rejects anything that is not a DateTime" do
      assert_raise FunctionClauseError, fn -> call(Time, :local_date, [~D[2026-10-31]]) end
    end
  end

  describe "time_label/1" do
    test "renders a zero-padded HH:MM in the display timezone" do
      assert Time.time_label(@noon) == "12:00"
      assert Time.time_label(~U[2026-10-31 15:05:00Z]) == "00:05"
      assert Time.time_label(~U[2026-10-31 23:59:00Z]) == "08:59"
    end

    test "ignores seconds" do
      assert Time.time_label(~U[2026-10-31 03:00:59Z]) == "12:00"
    end

    test "rejects anything that is not a DateTime" do
      assert_raise FunctionClauseError, fn -> call(Time, :time_label, [~D[2026-10-31]]) end
    end
  end

  describe "date_label/2" do
    test "labels the three most recent days" do
      assert Time.date_label(~D[2026-11-01], @today) == "今日"
      assert Time.date_label(~D[2026-10-31], @today) == "昨日"
      assert Time.date_label(~D[2026-10-30], @today) == "一昨日"
    end

    test "falls back to month and day plus weekday within the same year" do
      assert Time.date_label(~D[2026-10-28], @today) == "10月28日 (水)"
      assert Time.date_label(~D[2026-01-05], @today) == "1月5日 (月)"
    end

    test "prefixes the year when it differs from today's year" do
      assert Time.date_label(~D[2025-12-01], @today) == "2025年12月1日 (月)"
      assert Time.date_label(~D[2027-04-01], @today) == "2027年4月1日 (木)"
    end

    test "renders weekday parens without an inner space" do
      label = Time.date_label(~D[2026-10-26], @today)
      assert label == "10月26日 (月)"
      refute String.contains?(label, " ( ")
    end

    test "rejects anything that is not a Date" do
      assert_raise FunctionClauseError, fn -> call(Time, :date_label, [@noon, @today]) end
      assert_raise FunctionClauseError, fn -> call(Time, :date_label, [@today, "2026-11-01"]) end
    end
  end

  describe "weekday_label/1" do
    test "maps every weekday to its Japanese name" do
      dates = [
        ~D[2026-10-26],
        ~D[2026-10-27],
        ~D[2026-10-28],
        ~D[2026-10-29],
        ~D[2026-10-30],
        ~D[2026-10-31],
        ~D[2026-11-01]
      ]

      assert Enum.map(dates, &Time.weekday_label/1) == [
               "月",
               "火",
               "水",
               "木",
               "金",
               "土",
               "日"
             ]
    end

    test "rejects anything that is not a Date" do
      assert_raise FunctionClauseError, fn -> call(Time, :weekday_label, [@noon]) end
    end
  end

  describe "same_day?/2" do
    test "compares display-timezone dates, not UTC dates" do
      assert Time.same_day?(~U[2026-10-31 03:00:00Z], ~U[2026-10-31 11:59:00Z])
      refute Time.same_day?(~U[2026-10-31 03:00:00Z], ~U[2026-10-31 16:00:00Z])
    end

    test "is reflexive" do
      assert Time.same_day?(@noon, @noon)
    end

    test "does not guard its arguments" do
      assert_raise FunctionClauseError, fn -> Time.same_day?(nil, @noon) end
      assert_raise FunctionClauseError, fn -> Time.same_day?(@noon, nil) end
    end
  end
end
