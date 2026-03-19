defmodule JidoSessions.Parsers.Codex do
  @moduledoc """
  Parses raw Codex events into canonical `Turn` structs.

  Codex uses `response_item` events with nested `payload` objects.
  Payload type discriminates: message, function_call, function_call_output, reasoning.
  """

  alias JidoSessions.Turn
  alias JidoSessions.Parsers.Helpers

  @skip_types ~w[session_meta compacted event_msg]

  @spec parse_turns([map()]) :: [Turn.t()]
  def parse_turns(events) do
    tool_results = index_tool_results(events)

    events
    |> Enum.reject(fn e -> e.type in @skip_types end)
    |> chunk_into_turns()
    |> Enum.with_index()
    |> Enum.map(fn {turn_events, index} ->
      build_turn(turn_events, index, tool_results)
    end)
  end

  defp index_tool_results(events) do
    events
    |> Enum.filter(fn e ->
      payload = (e.data || %{})["payload"] || %{}
      payload["type"] in ["function_call_output", "custom_tool_call_output"]
    end)
    |> Map.new(fn e ->
      payload = e.data["payload"]
      call_id = payload["call_id"] || payload["id"]
      output = payload["output"] || ""
      output_str = if is_binary(output), do: output, else: Jason.encode!(output)
      {call_id, %{"result" => output_str, "success" => true}}
    end)
  end

  defp chunk_into_turns(events) do
    {turns, current} =
      Enum.reduce(events, {[], []}, fn event, {turns, current} ->
        payload = (event.data || %{})["payload"] || %{}

        if event.type == "turn_context" ||
             (payload["role"] == "user" && user_message?(payload)) do
          if current != [] do
            {turns ++ [current], [event]}
          else
            {turns, [event]}
          end
        else
          {turns, current ++ [event]}
        end
      end)

    if current != [], do: turns ++ [current], else: turns
  end

  defp user_message?(payload) do
    content = payload["content"]
    is_list(content) && Enum.any?(content, &(is_map(&1) && &1["type"] == "input_text"))
  end

  defp build_turn(events, index, tool_results) do
    {user_text, texts, reasoning_texts, tool_calls} =
      Enum.reduce(events, {nil, [], [], []}, fn event, {user, texts, reasoning, tools} ->
        payload = (event.data || %{})["payload"] || %{}
        role = payload["role"]
        content = payload["content"]
        payload_type = payload["type"]

        cond do
          event.type == "turn_context" ->
            text = extract_user_text(event.data)
            {text || user, texts, reasoning, tools}

          role == "user" && is_list(content) ->
            text =
              content
              |> Enum.flat_map(fn
                %{"type" => "input_text", "text" => t} when is_binary(t) -> [t]
                _ -> []
              end)
              |> Enum.join("\n")
              |> String.trim()

            if text != "" && !String.starts_with?(text, "#") && !String.starts_with?(text, "<") do
              {text, texts, reasoning, tools}
            else
              {user, texts, reasoning, tools}
            end

          role == "assistant" && is_list(content) ->
            new_texts =
              content
              |> Enum.flat_map(fn
                %{"type" => t, "text" => text}
                when t in ["output_text", "text"] and is_binary(text) and text != "" ->
                  [text]

                _ ->
                  []
              end)

            {user, texts ++ new_texts, reasoning, tools}

          payload_type in ["function_call", "custom_tool_call"] ->
            name = payload["name"] || payload["function"] || "tool"
            call_id = payload["call_id"] || payload["id"]
            args = Helpers.parse_arguments(payload["arguments"])
            result_data = Map.get(tool_results, call_id)

            tc =
              Helpers.build_tool_call(
                name,
                args,
                id: call_id,
                result: result_data && result_data["result"],
                success?: result_data && result_data["success"]
              )

            {user, texts, reasoning, tools ++ [tc]}

          payload_type == "reasoning" ->
            text = payload["text"] || payload["content"]

            if is_binary(text) && String.trim(text) != "" do
              {user, texts, reasoning ++ [text], tools}
            else
              {user, texts, reasoning, tools}
            end

          true ->
            {user, texts, reasoning, tools}
        end
      end)

    %Turn{
      index: index,
      user_content: user_text,
      reasoning: if(reasoning_texts != [], do: Enum.join(reasoning_texts, "\n\n")),
      assistant_content: if(texts != [], do: Enum.join(texts, "\n\n")),
      tool_calls: tool_calls
    }
  end

  defp extract_user_text(%{"content" => content}) when is_binary(content), do: content
  defp extract_user_text(_), do: nil
end
