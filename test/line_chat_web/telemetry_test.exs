defmodule LineChatWeb.TelemetryTest do
  @moduledoc """
  Checks the metric list the telemetry supervisor registers, covering Phoenix
  request/socket timings and the periodic VM measurements.
  """

  use ExUnit.Case, async: false

  alias Telemetry.Metrics.{Sum, Summary}

  @names [
    "phoenix.endpoint.start.system_time",
    "phoenix.endpoint.stop.duration",
    "phoenix.router_dispatch.start.system_time",
    "phoenix.router_dispatch.exception.duration",
    "phoenix.router_dispatch.stop.duration",
    "phoenix.socket_connected.duration",
    "phoenix.socket_drain.count",
    "phoenix.channel_joined.duration",
    "phoenix.channel_handled_in.duration",
    "vm.memory.total",
    "vm.total_run_queue_lengths.total",
    "vm.total_run_queue_lengths.cpu",
    "vm.total_run_queue_lengths.io"
  ]

  test "metrics/0 registers every Phoenix and VM metric with its unit and tags" do
    metrics = LineChatWeb.Telemetry.metrics()

    assert length(metrics) == length(@names)

    assert Enum.map(metrics, fn metric -> metric.__struct__ end) == [
             Summary,
             Summary,
             Summary,
             Summary,
             Summary,
             Summary,
             Sum,
             Summary,
             Summary,
             Summary,
             Summary,
             Summary,
             Summary
           ]

    assert Enum.map(metrics, fn metric -> Enum.join(metric.name, ".") end) == @names

    assert Enum.map(metrics, fn metric -> metric.tags end) == [
             [],
             [],
             [:route],
             [:route],
             [:route],
             [],
             [],
             [],
             [:event],
             [],
             [],
             [],
             []
           ]

    assert Enum.map(metrics, fn metric -> metric.unit end) == [
             :millisecond,
             :millisecond,
             :millisecond,
             :millisecond,
             :millisecond,
             :millisecond,
             :unit,
             :millisecond,
             :millisecond,
             :kilobyte,
             :unit,
             :unit,
             :unit
           ]
  end
end
