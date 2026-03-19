defmodule JidoSessions.Parsers.Copilot do
  @moduledoc """
  Parses raw Copilot CLI events into canonical `Turn` structs.

  Copilot events have explicit types: `assistant.message`, `tool.execution_start`,
  `tool.execution_complete`, `user.message`, `assistant.turn_start`, etc.
  Tool calls are split into start/complete pairs that must be merged.
  """

  alias JidoSessions.Turn
  alias JidoSessions.Parsers.Helpers

  @noise_types MapSet.new([
                 "session.truncation",
                 "session.start",
                 "session.model_change",
                 "session.compaction_start",
                 "session.compaction_complete",
                 "session.plan_changed",
                 "session.resume",
                 "session.shutdown",
                 "session.context_changed",
                 "session.mode_changed",
                 "session.workspace_file_changed",
                 "session.usage_info",
                 "hook.start",
                 "hook.end",
                 "permission.requested",
                 "permission.completed",
                 "tool.user_requested",
                 "tool.execution_partial_result",
                 "external_tool.completed",
                 "session.background_tasks_changed",
                 "session.tools_updated",
                 "pending_messages.modified"
               ])

  @doc """
  Parses a list of raw Copilot events into a list of `Turn` structs.
  """
  @spec parse_turns([map()]) :: [Turn.t()]
  def parse_turns(events) do
    tool_results = index_tool_results(events)

    events
    |> Enum.reject(fn e -> MapSet.member?(@noise_types, e.type) end)
    |> chunk_into_turns()
    |> Enum.with_index()
    |> Enum.map(fn {turn_events, index} ->
      build_turn(turn_events, index, tool_results)
    end)
  end

  defp index_tool_results(events) do
    events
    |> Enum.filter(&(&1.type == "tool.execution_complete"))
    |> Map.new(fn e -> {e.data["toolCallId"], e.data} end)
  end

  defp chunk_into_turns(events) do
    {turns, current} =
      Enum.reduce(events, {[], []}, fn event, {turns, current} ->
        if event.type == "user.message" && current != [] do
          {turns ++ [current], [event]}
        else
          {turns, current ++ [event]}
        end
      end)

    if current != [], do: turns ++ [current], else: turns
  end

  defp build_turn(events, index, tool_results) do
    user_msg = Enum.find(events, &(&1.type == "user.message"))

    {assistant_text, reasoning_texts} =
      events
      |> Enum.filter(&(&1.type == "assistant.message"))
      |> Enum.reduce({"", []}, fn e, {text, reasoning} ->
        chunk = e.data["chunkContent"] || e.data["content"] || ""
        r = e.data["reasoningText"]

        reasoning =
          if is_binary(r) && String.trim(r) != "", do: reasoning ++ [r], else: reasoning

        {text <> chunk, reasoning}
      end)

    standalone_reasoning =
      events
      |> Enum.filter(&(&1.type == "assistant.reasoning"))
      |> Enum.map(& &1.data["content"])
      |> Enum.filter(&is_binary/1)

    all_reasoning = reasoning_texts ++ standalone_reasoning

    # Build tool calls from tool.execution_start events, merging with results
    tool_calls =
      events
      |> Enum.filter(&(&1.type == "tool.execution_start"))
      |> Enum.map(fn e ->
        call_id = e.data["toolCallId"]
        result_data = Map.get(tool_results, call_id)
        args = Helpers.parse_arguments(e.data["arguments"])

        Helpers.build_tool_call(
          e.data["toolName"],
          args,
          id: call_id,
          result: result_data && (result_data["result"] || result_data["error"]),
          success?: result_data && result_data["success"]
        )
      end)

    # Also build tool calls from toolRequests embedded in assistant.message
    embedded_tool_calls =
      events
      |> Enum.filter(&(&1.type == "assistant.message"))
      |> Enum.flat_map(fn e ->
        (e.data["toolRequests"] || [])
        |> Enum.reject(fn req -> req["name"] in ["report_intent"] end)
        |> Enum.filter(fn req ->
          call_id = req["toolCallId"]
          not Enum.any?(tool_calls, &(&1.id == call_id))
        end)
        |> Enum.map(fn req ->
          call_id = req["toolCallId"]
          args = Helpers.parse_arguments(req["arguments"])
          result_data = Map.get(tool_results, call_id)

          Helpers.build_tool_call(
            req["name"],
            args,
            id: call_id,
            result: result_data && (result_data["result"] || result_data["error"]),
            success?: result_data && result_data["success"]
          )
        end)
      end)

    usage_event = Enum.find(events, &(&1.type == "assistant.usage"))
    usage = if usage_event, do: Helpers.parse_usage(usage_event.data), else: nil

    turn_start = Enum.find(events, &(&1.type == "assistant.turn_start"))
    timestamp = (turn_start && turn_start[:timestamp]) || (user_msg && user_msg[:timestamp])

    %Turn{
      index: index,
      started_at: timestamp,
      user_content: user_msg && user_msg.data["content"],
      user_attachments: (user_msg && user_msg.data["attachments"]) || [],
      reasoning: if(all_reasoning != [], do: Enum.join(all_reasoning, "\n\n")),
      assistant_content: if(String.trim(assistant_text) != "", do: assistant_text),
      tool_calls: tool_calls ++ embedded_tool_calls,
      usage: usage
    }
  end
end
