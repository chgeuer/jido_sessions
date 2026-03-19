defmodule JidoSessions.Handoff.Extractor do
  @moduledoc """
  Extracts structured information from canonical turns for handoff generation.

  Classifies tool calls into operations (file reads, writes, commands, searches)
  and identifies the session's last user goal and incomplete work.
  """

  alias JidoSessions.ToolCall
  alias JidoSessions.Tools

  defstruct operations: [],
            files_read: [],
            files_written: [],
            commands: [],
            searches: [],
            last_user_goal: nil,
            incomplete_tools: 0

  @type t :: %__MODULE__{}

  @doc "Extracts structured data from a list of turns."
  @spec extract([JidoSessions.Turn.t()]) :: t()
  def extract(turns) do
    state = %__MODULE__{}

    state =
      Enum.reduce(turns, state, fn turn, state ->
        state =
          if turn.user_content, do: %{state | last_user_goal: turn.user_content}, else: state

        Enum.reduce(turn.tool_calls, state, fn tc, state ->
          classify_tool_call(state, tc)
        end)
      end)

    incomplete =
      turns
      |> Enum.flat_map(& &1.tool_calls)
      |> Enum.count(&(&1.success? == nil))

    %{state | incomplete_tools: incomplete}
  end

  defp classify_tool_call(state, %ToolCall{tool: :shell} = tc) do
    command = extract_command(tc.arguments)
    output = extract_output(tc.result)

    cmd = %{command: command, output: output, success?: tc.success?}
    %{state | commands: state.commands ++ [cmd], operations: state.operations ++ [tc]}
  end

  defp classify_tool_call(state, %ToolCall{tool: :file_read} = tc) do
    path = extract_path(tc.arguments)

    %{
      state
      | files_read: state.files_read ++ [path],
        operations: state.operations ++ [tc]
    }
  end

  defp classify_tool_call(state, %ToolCall{tool: tool} = tc)
       when tool in [:file_create, :file_edit, :file_patch] do
    path = extract_path(tc.arguments)

    %{
      state
      | files_written: state.files_written ++ [path],
        operations: state.operations ++ [tc]
    }
  end

  defp classify_tool_call(state, %ToolCall{tool: tool} = tc)
       when tool in [:search_content, :search_files] do
    %{
      state
      | searches: state.searches ++ [tc],
        operations: state.operations ++ [tc]
    }
  end

  defp classify_tool_call(state, %ToolCall{} = tc) do
    %{state | operations: state.operations ++ [tc]}
  end

  defp extract_command(%Tools.Shell.Args{command: cmd}), do: cmd
  defp extract_command(%{command: cmd}) when is_binary(cmd), do: cmd
  defp extract_command(_), do: ""

  defp extract_output(%Tools.Shell.Result{output: output}), do: output
  defp extract_output(%{output: output}) when is_binary(output), do: output
  defp extract_output(_), do: nil

  defp extract_path(%Tools.File.ReadArgs{path: path}), do: path
  defp extract_path(%Tools.File.CreateArgs{path: path}), do: path
  defp extract_path(%Tools.File.EditArgs{path: path}), do: path
  defp extract_path(%{path: path}) when is_binary(path), do: path
  defp extract_path(_), do: "unknown"
end
