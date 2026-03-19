defmodule JidoSessions.Parsers.Helpers do
  @moduledoc "Shared utilities for agent event parsers."

  alias JidoSessions.{ToolCall, ToolNames, Usage}
  alias JidoSessions.Tools

  @doc "Builds a ToolCall from a tool name, arguments map, and optional result."
  def build_tool_call(name, args_map, opts \\ []) do
    tool = ToolNames.canonicalize(name || "unknown")

    %ToolCall{
      id: opts[:id],
      tool: tool,
      arguments: build_arguments(tool, args_map || %{}),
      result: build_result(tool, opts[:result]),
      success?: opts[:success?],
      started_at: opts[:started_at],
      completed_at: opts[:completed_at]
    }
  end

  @doc "Builds typed arguments struct from a canonical tool atom and raw args map."
  def build_arguments(tool, args) when is_map(args) do
    case tool do
      :shell ->
        %Tools.Shell.Args{
          command: get_command(args),
          workdir: args["workdir"] || args["working_directory"],
          description: args["description"],
          timeout_ms: args["timeout_ms"] || args["initial_wait"]
        }

      :shell_read ->
        %Tools.ShellIO.ReadArgs{
          session_id: to_string(args["session_id"] || args["shellId"] || ""),
          timeout_ms: args["timeout_ms"] || args["delay"]
        }

      :shell_write ->
        %Tools.ShellIO.WriteArgs{
          session_id: to_string(args["session_id"] || args["shellId"] || ""),
          input: args["input"] || args["chars"] || ""
        }

      :shell_stop ->
        %Tools.ShellIO.StopArgs{
          session_id: to_string(args["session_id"] || args["shellId"] || "")
        }

      :shell_list ->
        %Tools.ShellIO.ListArgs{}

      :file_read ->
        range = parse_line_range(args["view_range"] || args["line_range"])

        %Tools.File.ReadArgs{
          path: args["path"] || args["file_path"] || "",
          line_range: range
        }

      :file_create ->
        %Tools.File.CreateArgs{
          path: args["path"] || args["file_path"] || "",
          content: args["file_text"] || args["content"] || ""
        }

      :file_edit ->
        %Tools.File.EditArgs{
          path: args["path"] || args["file_path"] || "",
          old_text: args["old_str"] || args["old_text"] || args["old_string"] || "",
          new_text: args["new_str"] || args["new_text"] || args["new_string"] || ""
        }

      :file_patch ->
        %Tools.File.PatchArgs{
          patch: args["patch"] || args["input"] || "",
          base_path: args["base_path"]
        }

      :search_content ->
        %Tools.Search.ContentArgs{
          pattern: args["pattern"] || args["query"] || args["content"] || "",
          path: args["path"],
          file_type: args["type"] || args["file_type"],
          case_sensitive?: Map.get(args, "case_sensitive", true),
          max_results: args["head_limit"] || args["max_results"]
        }

      :search_files ->
        %Tools.Search.FilesArgs{
          pattern: args["pattern"] || "",
          path: args["path"]
        }

      :ask_user ->
        choices = parse_choices(args["choices"])

        %Tools.Interaction.AskUserArgs{
          question: args["question"] || "",
          choices: choices,
          allow_freeform?: Map.get(args, "allow_freeform", true)
        }

      :task_create ->
        %Tools.Agent.CreateArgs{
          agent_type: args["agent_type"],
          name: args["name"],
          description: args["description"],
          prompt: args["prompt"] || ""
        }

      :task_read ->
        %Tools.Agent.ReadArgs{
          agent_id: args["agent_id"] || ""
        }

      :task_list ->
        %Tools.Agent.ListArgs{}

      :web_search ->
        %Tools.Web.SearchArgs{
          query: args["query"] || ""
        }

      :web_fetch ->
        %Tools.Web.FetchArgs{
          url: args["url"] || "",
          max_length: args["max_length"]
        }

      :intent ->
        %Tools.Interaction.IntentArgs{
          intent: args["intent"] || args["plan"] || ""
        }

      :todo_update ->
        %Tools.Interaction.TodoUpdateArgs{
          todo_id: args["id"] || args["todo_id"] || "",
          title: args["title"],
          status: args["status"],
          description: args["description"]
        }

      :sql ->
        %Tools.Interaction.SqlArgs{
          query: args["query"] || "",
          database: args["database"],
          description: args["description"]
        }

      :memory ->
        %Tools.Interaction.MemoryArgs{
          subject: args["subject"] || "",
          fact: args["fact"] || "",
          reason: args["reason"]
        }

      :skill ->
        %Tools.Skill.Args{
          skill: args["skill"] || args["name"] || "",
          extra: Map.drop(args, ["skill", "name"])
        }

      :github_api ->
        %Tools.GitHub.Args{
          method: args["method"] || "",
          owner: args["owner"],
          repo: args["repo"],
          query: args["query"],
          extra: Map.drop(args, ["method", "owner", "repo", "query"])
        }

      :unknown ->
        args
    end
  end

  def build_arguments(_tool, args), do: args

  @doc "Builds typed result struct from canonical tool atom and raw result data."
  def build_result(_tool, nil), do: nil

  def build_result(tool, result) when is_binary(result) do
    build_result(tool, %{"output" => result})
  end

  def build_result(tool, result) when is_map(result) do
    output = result["output"] || result["result"] || result["content"]

    case tool do
      t when t in [:shell, :shell_read, :shell_write] ->
        %Tools.Shell.Result{
          output: output,
          exit_status: result["exit_status"] || result["exitCode"]
        }

      :shell_stop ->
        %Tools.ShellIO.Result{output: output}

      :shell_list ->
        %Tools.ShellIO.Result{output: output}

      :file_read ->
        %Tools.File.ReadResult{content: output, size: result["size"]}

      t when t in [:file_create, :file_edit] ->
        %Tools.File.WriteResult{}

      :file_patch ->
        %Tools.File.PatchResult{files_changed: result["files_changed"] || []}

      :search_content ->
        %Tools.Search.ContentResult{
          matches: output,
          match_count: result["match_count"]
        }

      :search_files ->
        files =
          result["files"] ||
            if(is_binary(output), do: String.split(output, "\n", trim: true), else: [])

        %Tools.Search.FilesResult{files: files, file_count: length(files)}

      :ask_user ->
        %Tools.Interaction.AskUserResult{response: output}

      :task_create ->
        %Tools.Agent.CreateResult{agent_id: result["agent_id"], status: result["status"]}

      :task_read ->
        %Tools.Agent.ReadResult{status: result["status"], output: output}

      :task_list ->
        %Tools.Agent.ListResult{agents: result["agents"] || []}

      :web_search ->
        %Tools.Web.SearchResult{content: output, sources: result["sources"] || []}

      :web_fetch ->
        %Tools.Web.FetchResult{content: output, content_type: result["content_type"]}

      :sql ->
        %Tools.Interaction.SqlResult{rows: result["rows"] || [], row_count: result["row_count"]}

      _ ->
        %{output: output}
    end
  end

  def build_result(_, result), do: result

  @doc "Parses arguments that might be a JSON string into a map."
  def parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{"input" => args}
    end
  end

  def parse_arguments(args) when is_map(args), do: args
  def parse_arguments(_), do: %{}

  defp get_command(args) do
    case args do
      %{"command" => cmd} when is_binary(cmd) -> cmd
      %{"command" => cmd} when is_list(cmd) -> Enum.join(cmd, " ")
      %{"cmd" => cmd} when is_binary(cmd) -> cmd
      _ -> ""
    end
  end

  defp parse_choices(nil), do: []
  defp parse_choices(choices) when is_list(choices), do: choices

  defp parse_choices(choices) when is_binary(choices) do
    String.split(choices, ",") |> Enum.map(&String.trim/1)
  end

  defp parse_choices(_), do: []

  defp parse_line_range(nil), do: nil

  defp parse_line_range([start, stop]) when is_integer(start) and is_integer(stop),
    do: {start, stop}

  defp parse_line_range(_), do: nil

  @doc "Parses a Usage struct from raw token data."
  def parse_usage(data) when is_map(data) do
    %Usage{
      model: data["model"],
      input_tokens: data["inputTokens"] || data["input_tokens"] || 0,
      output_tokens: data["outputTokens"] || data["output_tokens"] || 0,
      cache_read_tokens: data["cacheReadTokens"] || data["cache_read_tokens"] || 0,
      cache_write_tokens: data["cacheWriteTokens"] || data["cache_write_tokens"] || 0,
      cost: data["cost"],
      duration_ms: data["duration"] || data["duration_ms"],
      initiator: data["initiator"]
    }
  end

  def parse_usage(_), do: nil
end
