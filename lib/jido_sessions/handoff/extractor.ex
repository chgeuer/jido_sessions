defmodule JidoSessions.Handoff.Extractor do
  @moduledoc """
  Extracts structured information from canonical turns for handoff generation.

  Classifies tool calls into operations (file reads, writes, commands, searches)
  and identifies the session's last user goal and incomplete work.
  """

  alias JidoSessions.{Turn, ToolCall}
  alias JidoSessions.Tools

  defmodule Operation do
    @moduledoc "A classified operation extracted from a tool call."

    @type kind :: :file_read | :file_write | :file_delete | :search | :command | :intent | :other
    @type confidence :: :structured | :inferred | :unknown

    @type t :: %__MODULE__{
            kind: kind(),
            action: String.t() | nil,
            tool: atom() | nil,
            path: String.t() | nil,
            paths: [String.t()],
            read_span: String.t() | nil,
            command: String.t() | nil,
            workdir: String.t() | nil,
            summary: String.t() | nil,
            result_excerpt: String.t() | nil,
            success: boolean() | nil,
            error: String.t() | nil,
            command_class: String.t() | nil,
            confidence: confidence(),
            turn_index: non_neg_integer() | nil,
            started_at: DateTime.t() | nil,
            completed_at: DateTime.t() | nil,
            started_sequence: non_neg_integer() | nil,
            completed_sequence: non_neg_integer() | nil,
            timestamp: DateTime.t() | nil
          }

    defstruct [
      :kind,
      :action,
      :tool,
      :path,
      :read_span,
      :command,
      :workdir,
      :summary,
      :result_excerpt,
      :success,
      :error,
      :command_class,
      :turn_index,
      :started_at,
      :completed_at,
      :started_sequence,
      :completed_sequence,
      :timestamp,
      paths: [],
      confidence: :structured
    ]
  end

  @doc "Extracts structured data from a list of canonical turns."
  @spec extract([Turn.t()]) :: map()
  @spec extract([Turn.t()], keyword()) :: map()
  def extract(turns, opts \\ []) do
    cwd = Keyword.get(opts, :cwd)

    {prompts, assistant_outputs} = extract_transcript(turns)
    operations = extract_operations(turns, cwd)

    %{
      prompts: prompts,
      assistant_outputs: assistant_outputs,
      operations: operations,
      last_user_goal: derive_last_user_goal(turns),
      incomplete_tools: count_incomplete_tools(turns),
      files_read: derive_files_read(operations),
      files_written: derive_files_written(operations),
      commands: derive_commands(operations),
      searches: derive_searches(operations)
    }
  end

  # ── Transcript extraction ──

  defp extract_transcript(turns) do
    {prompts, outputs} =
      Enum.reduce(turns, {[], []}, fn turn, {prompts_acc, outputs_acc} ->
        prompts_acc =
          if turn.user_content && String.trim(turn.user_content) != "" do
            entry = %{
              index: turn.index,
              timestamp: turn.started_at,
              text: turn.user_content,
              sequence: turn.index
            }

            [entry | prompts_acc]
          else
            prompts_acc
          end

        outputs_acc =
          if turn.assistant_content && String.trim(turn.assistant_content) != "" do
            entry = %{
              index: turn.index,
              timestamp: turn.started_at,
              text: turn.assistant_content,
              sequence_start: turn.index,
              sequence_end: turn.index
            }

            [entry | outputs_acc]
          else
            outputs_acc
          end

        {prompts_acc, outputs_acc}
      end)

    {Enum.reverse(prompts), Enum.reverse(outputs)}
  end

  # ── Operation extraction ──

  defp extract_operations(turns, cwd) do
    turns
    |> Enum.flat_map(fn turn ->
      Enum.flat_map(turn.tool_calls, &classify_tool_call(&1, turn, cwd))
    end)
    |> Enum.sort_by(&{&1.turn_index || 0, to_string(&1.tool)})
  end

  defp classify_tool_call(%ToolCall{tool: :shell} = tc, turn, cwd) do
    command = extract_shell_command(tc.arguments)
    output = extract_shell_output(tc.result)
    workdir = extract_shell_workdir(tc.arguments) || cwd
    description = extract_shell_description(tc.arguments)

    command_op = %Operation{
      kind: :command,
      tool: :shell,
      command: command,
      workdir: workdir,
      summary: description,
      result_excerpt: output,
      success: tc.success?,
      command_class: classify_command(command),
      confidence: :structured,
      turn_index: turn.index,
      started_at: tc.started_at,
      completed_at: tc.completed_at,
      started_sequence: turn.index,
      completed_sequence: turn.index,
      timestamp: tc.started_at || turn.started_at
    }

    [command_op | infer_shell_operations(command, turn, workdir)]
  end

  defp classify_tool_call(%ToolCall{tool: :file_read} = tc, turn, _cwd) do
    path = extract_file_path(tc.arguments)

    if path do
      [
        %Operation{
          kind: :file_read,
          tool: :file_read,
          path: path,
          paths: [path],
          read_span: extract_read_span(tc.arguments),
          success: tc.success?,
          confidence: :structured,
          turn_index: turn.index,
          started_at: tc.started_at,
          completed_at: tc.completed_at,
          started_sequence: turn.index,
          completed_sequence: turn.index,
          timestamp: tc.started_at || turn.started_at
        }
      ]
    else
      []
    end
  end

  defp classify_tool_call(%ToolCall{tool: :file_patch} = tc, turn, _cwd) do
    parse_patch_operations(tc, turn)
  end

  defp classify_tool_call(%ToolCall{tool: tool} = tc, turn, _cwd)
       when tool in [:file_create, :file_edit] do
    path = extract_file_path(tc.arguments)
    action = if tool == :file_create, do: "created", else: "modified"

    if path do
      [
        %Operation{
          kind: :file_write,
          action: action,
          tool: tool,
          path: path,
          paths: [path],
          success: tc.success?,
          confidence: :structured,
          turn_index: turn.index,
          started_at: tc.started_at,
          completed_at: tc.completed_at,
          started_sequence: turn.index,
          completed_sequence: turn.index,
          timestamp: tc.started_at || turn.started_at
        }
      ]
    else
      []
    end
  end

  defp classify_tool_call(%ToolCall{tool: tool} = tc, turn, _cwd)
       when tool in [:search_content, :search_files] do
    {pattern, path} = extract_search_info(tc.arguments)

    summary =
      [pattern && "pattern=#{pattern}", path && "path=#{path}"]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    [
      %Operation{
        kind: :search,
        tool: tool,
        path: path,
        paths: List.wrap(path),
        summary: if(summary == "", do: inspect(tc.arguments), else: summary),
        result_excerpt: extract_search_result(tc.result),
        success: tc.success?,
        confidence: :structured,
        turn_index: turn.index,
        started_at: tc.started_at,
        completed_at: tc.completed_at,
        started_sequence: turn.index,
        completed_sequence: turn.index,
        timestamp: tc.started_at || turn.started_at
      }
    ]
  end

  defp classify_tool_call(%ToolCall{tool: :intent} = tc, turn, _cwd) do
    [
      %Operation{
        kind: :intent,
        tool: :intent,
        summary: extract_intent_text(tc.arguments),
        confidence: :structured,
        turn_index: turn.index,
        started_at: tc.started_at,
        completed_at: tc.completed_at,
        started_sequence: turn.index,
        completed_sequence: turn.index,
        timestamp: tc.started_at || turn.started_at
      }
    ]
  end

  defp classify_tool_call(%ToolCall{} = tc, turn, _cwd) do
    [
      %Operation{
        kind: :other,
        tool: tc.tool,
        success: tc.success?,
        confidence: :structured,
        turn_index: turn.index,
        started_at: tc.started_at,
        completed_at: tc.completed_at,
        started_sequence: turn.index,
        completed_sequence: turn.index,
        timestamp: tc.started_at || turn.started_at
      }
    ]
  end

  # ── Shell inference ──

  defp infer_shell_operations(command, turn, workdir) when is_binary(command) do
    command
    |> split_command_fragments()
    |> Enum.flat_map(&infer_shell_fragment(&1, turn, workdir))
  end

  defp infer_shell_operations(_command, _turn, _workdir), do: []

  defp infer_shell_fragment(fragment, turn, workdir) do
    line = String.trim(fragment)

    base = %Operation{
      confidence: :inferred,
      tool: :shell,
      turn_index: turn.index,
      workdir: workdir,
      started_sequence: turn.index,
      completed_sequence: turn.index,
      timestamp: turn.started_at
    }

    search_ops =
      if Regex.match?(~r/\b(rg|grep|find|fd)\b/, line) do
        [%{base | kind: :search, summary: line}]
      else
        []
      end

    read_ops = inferred_read_operations(line, base)
    write_ops = inferred_write_operations(line, base)
    move_ops = inferred_move_operations(line, base)

    search_ops ++ read_ops ++ write_ops ++ move_ops
  end

  defp inferred_read_operations(line, base) do
    sed_reads =
      Regex.scan(~r/\bsed\s+-n\s+['"]?(\d+),(\d+)p['"]?\s+(['"]?)([^'"\s|&;]+)\3/, line)
      |> Enum.map(fn [_, start_line, end_line, _, path] ->
        %{base | kind: :file_read, path: path, paths: [path], read_span: "#{start_line}-#{end_line}"}
      end)

    head_reads =
      Regex.scan(~r/\bhead(?:\s+-n\s+(\d+))?(?:\s+-[^\s]+\s+)*(['"]?)([^'"\s|&;]+)\2/, line)
      |> Enum.map(fn [_, count, _, path] ->
        span = if count == "", do: nil, else: "1-#{count}"
        %{base | kind: :file_read, path: path, paths: [path], read_span: span}
      end)

    tail_reads =
      Regex.scan(~r/\btail(?:\s+-n\s+(\d+))?(?:\s+-[^\s]+\s+)*(['"]?)([^'"\s|&;]+)\2/, line)
      |> Enum.map(fn [_, count, _, path] ->
        span = if count == "", do: nil, else: "last #{count} lines"
        %{base | kind: :file_read, path: path, paths: [path], read_span: span}
      end)

    cat_reads =
      Regex.scan(~r/\bcat\s+(['"]?)([^'"\s|&;]+)\1/, line)
      |> Enum.map(fn [_, _, path] ->
        %{base | kind: :file_read, path: path, paths: [path]}
      end)

    sed_reads ++ head_reads ++ tail_reads ++ cat_reads
  end

  defp inferred_write_operations(line, base) do
    redirections =
      Regex.scan(~r/(?:>>|>)\s*(['"]?)([^'"\s|&;]+)\1/, line)
      |> Enum.map(fn [_, _, path] ->
        %{base | kind: :file_write, action: "written", path: path, paths: [path]}
      end)

    tees =
      Regex.scan(~r/\btee\s+(?:-a\s+)?(['"]?)([^'"\s|&;]+)\1/, line)
      |> Enum.map(fn [_, _, path] ->
        %{base | kind: :file_write, action: "written", path: path, paths: [path]}
      end)

    mkdirs =
      Regex.scan(~r/\bmkdir\s+(?:-p\s+)?(['"]?)([^'"\s|&;]+)\1/, line)
      |> Enum.map(fn [_, _, path] ->
        %{base | kind: :file_write, action: "directory_created", path: path, paths: [path]}
      end)

    touches =
      Regex.scan(~r/\btouch\s+(['"]?)([^'"\s|&;]+)\1/, line)
      |> Enum.map(fn [_, _, path] ->
        %{base | kind: :file_write, action: "created", path: path, paths: [path]}
      end)

    removals =
      Regex.scan(~r/\brm\s+(?:-[^\s]+\s+)*(['"]?)([^'"\s|&;]+)\1/, line)
      |> Enum.map(fn [_, _, path] ->
        %{base | kind: :file_delete, action: "deleted", path: path, paths: [path]}
      end)

    redirections ++ tees ++ mkdirs ++ touches ++ removals
  end

  defp inferred_move_operations(line, base) do
    case Regex.run(
           ~r/\b(cp|mv)\s+(?:-[^\s]+\s+)*(['"]?)([^'"\s|&;]+)\2\s+(['"]?)([^'"\s|&;]+)\4/,
           line
         ) do
      [_, cmd, _, source, _, destination] ->
        [
          %{base | kind: :file_read, path: source, paths: [source]},
          %{base
           | kind: :file_write,
             action: if(cmd == "mv", do: "renamed", else: "created"),
             path: destination,
             paths: [destination]}
        ]

      _ ->
        []
    end
  end

  # ── Patch parsing ──

  defp parse_patch_operations(%ToolCall{} = tc, turn) do
    patch_text = extract_patch_text(tc.arguments)

    base = %Operation{
      tool: :file_patch,
      success: tc.success?,
      confidence: :structured,
      turn_index: turn.index,
      started_at: tc.started_at,
      completed_at: tc.completed_at,
      started_sequence: turn.index,
      completed_sequence: turn.index,
      timestamp: tc.started_at || turn.started_at
    }

    if patch_text do
      patch_text
      |> String.split("\n")
      |> Enum.flat_map(fn line ->
        cond do
          String.starts_with?(line, "*** Add File: ") ->
            path = String.replace_prefix(line, "*** Add File: ", "")
            [%{base | kind: :file_write, action: "created", path: path, paths: [path]}]

          String.starts_with?(line, "*** Update File: ") ->
            path = String.replace_prefix(line, "*** Update File: ", "")
            [%{base | kind: :file_write, action: "modified", path: path, paths: [path]}]

          String.starts_with?(line, "*** Delete File: ") ->
            path = String.replace_prefix(line, "*** Delete File: ", "")
            [%{base | kind: :file_delete, action: "deleted", path: path, paths: [path]}]

          String.starts_with?(line, "*** Move to: ") ->
            path = String.replace_prefix(line, "*** Move to: ", "")
            [%{base | kind: :file_write, action: "renamed", path: path, paths: [path]}]

          true ->
            []
        end
      end)
      |> Enum.uniq_by(&{&1.kind, &1.action, &1.path})
    else
      changed = extract_patch_changed_files(tc.result)

      Enum.map(changed, fn path ->
        %{base | kind: :file_write, action: "modified", path: path, paths: [path]}
      end)
    end
  end

  # ── Command classification ──

  @doc false
  def classify_command(command) when not is_binary(command), do: "command"

  def classify_command(command) do
    downcased = String.downcase(command)

    cond do
      Regex.match?(~r/\bgit commit\b/, downcased) ->
        "git_commit"

      Regex.match?(
        ~r/\b(mix test|mix precommit|npm test|pnpm test|yarn test|go test|cargo test|pytest|rspec)\b/,
        downcased
      ) ->
        "test_run"

      Regex.match?(
        ~r/\b(mix phx\.server|iex -s mix phx\.server|npm run dev|pnpm dev|yarn dev|docker compose up)\b/,
        downcased
      ) ->
        "server_or_daemon"

      Regex.match?(
        ~r/\b(mix compile|npm run build|pnpm build|yarn build|cargo build|go build)\b/,
        downcased
      ) ->
        "build"

      Regex.match?(~r/\b(python|python3|node|ruby|perl|mix run|elixir)\b/, downcased) ->
        "code_execution"

      Regex.match?(~r/\bgit\b/, downcased) ->
        "version_control"

      Regex.match?(~r/\b(rg|grep|ls|cat|head|tail|find|fd|sed -n)\b/, downcased) ->
        "inspection"

      true ->
        "command"
    end
  end

  # ── Derivation helpers ──

  defp derive_files_read(operations) do
    operations
    |> Enum.filter(&(&1.kind == :file_read && is_binary(&1.path)))
    |> Enum.map(& &1.path)
    |> Enum.uniq()
  end

  defp derive_files_written(operations) do
    operations
    |> Enum.filter(&(&1.kind in [:file_write, :file_delete] && is_binary(&1.path)))
    |> Enum.map(& &1.path)
    |> Enum.uniq()
  end

  defp derive_commands(operations) do
    operations
    |> Enum.filter(&(&1.kind == :command && is_binary(&1.command)))
    |> Enum.map(fn op ->
      %{
        command: op.command,
        output: op.result_excerpt,
        success?: op.success,
        workdir: op.workdir,
        command_class: op.command_class
      }
    end)
  end

  defp derive_searches(operations) do
    operations
    |> Enum.filter(&(&1.kind == :search))
    |> Enum.map(fn op -> %{pattern: op.summary, path: op.path} end)
  end

  defp derive_last_user_goal(turns) do
    turns
    |> Enum.reverse()
    |> Enum.find_value(fn turn ->
      if turn.user_content && String.trim(turn.user_content) != "",
        do: turn.user_content
    end)
  end

  defp count_incomplete_tools(turns) do
    turns
    |> Enum.flat_map(& &1.tool_calls)
    |> Enum.count(&(&1.success? == nil))
  end

  # ── Argument extraction helpers ──

  defp extract_shell_command(%Tools.Shell.Args{command: cmd}), do: cmd
  defp extract_shell_command(%{command: cmd}) when is_binary(cmd), do: cmd
  defp extract_shell_command(_), do: nil

  defp extract_shell_output(%Tools.Shell.Result{output: output}), do: output
  defp extract_shell_output(%{output: output}) when is_binary(output), do: output
  defp extract_shell_output(_), do: nil

  defp extract_shell_workdir(%Tools.Shell.Args{workdir: workdir}), do: workdir
  defp extract_shell_workdir(%{workdir: workdir}) when is_binary(workdir), do: workdir
  defp extract_shell_workdir(_), do: nil

  defp extract_shell_description(%Tools.Shell.Args{description: desc}), do: desc
  defp extract_shell_description(%{description: desc}) when is_binary(desc), do: desc
  defp extract_shell_description(_), do: nil

  defp extract_file_path(%Tools.File.ReadArgs{path: path}), do: path
  defp extract_file_path(%Tools.File.CreateArgs{path: path}), do: path
  defp extract_file_path(%Tools.File.EditArgs{path: path}), do: path
  defp extract_file_path(%{path: path}) when is_binary(path), do: path
  defp extract_file_path(_), do: nil

  defp extract_read_span(%Tools.File.ReadArgs{line_range: {s, -1}}), do: "#{s}-end"

  defp extract_read_span(%Tools.File.ReadArgs{line_range: {s, e}}) when s == e,
    do: Integer.to_string(s)

  defp extract_read_span(%Tools.File.ReadArgs{line_range: {s, e}}), do: "#{s}-#{e}"
  defp extract_read_span(%Tools.File.ReadArgs{line_range: nil}), do: nil
  defp extract_read_span(_), do: nil

  defp extract_search_info(%Tools.Search.ContentArgs{pattern: p, path: path}), do: {p, path}
  defp extract_search_info(%Tools.Search.FilesArgs{pattern: p, path: path}), do: {p, path}
  defp extract_search_info(%{pattern: p, path: path}), do: {p, path}
  defp extract_search_info(%{pattern: p}), do: {p, nil}
  defp extract_search_info(_), do: {nil, nil}

  defp extract_search_result(%Tools.Search.ContentResult{matches: m}), do: m
  defp extract_search_result(%Tools.Search.FilesResult{files: f}), do: Enum.join(f, "\n")
  defp extract_search_result(%{matches: m}) when is_binary(m), do: m
  defp extract_search_result(_), do: nil

  defp extract_intent_text(%{intent: text}) when is_binary(text), do: text
  defp extract_intent_text(%{"intent" => text}) when is_binary(text), do: text
  defp extract_intent_text(args), do: inspect(args)

  defp extract_patch_text(%Tools.File.PatchArgs{patch: patch}), do: patch
  defp extract_patch_text(%{patch: patch}) when is_binary(patch), do: patch
  defp extract_patch_text(text) when is_binary(text), do: text
  defp extract_patch_text(_), do: nil

  defp extract_patch_changed_files(%Tools.File.PatchResult{files_changed: files}), do: files
  defp extract_patch_changed_files(%{files_changed: files}) when is_list(files), do: files
  defp extract_patch_changed_files(_), do: []

  defp split_command_fragments(command) do
    command
    |> String.split(["\n", "&&", ";"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
