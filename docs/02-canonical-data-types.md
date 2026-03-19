# Canonical Data Types

Structs representing the universal concepts found across all coding agent sessions.
These types form the interface boundary of `jido_sessions` — agent parsers produce
them, the session store persists them, and renderers consume them.

## Design principles

1. **Agent-agnostic**: No agent-specific fields. Agent identity is metadata on the session.
2. **Strongly typed tools**: Each tool category gets its own argument/result struct.
3. **Lossless round-trip**: Raw agent data preserved in `metadata` fields for debugging.
4. **Flat over nested**: Prefer top-level fields over deeply nested maps.

## Session

The root aggregate. One session = one human-agent conversation.

```elixir
%Session{
  id: "gh_ad9ae885-...",          # Prefixed with agent type
  agent: :copilot,                # :copilot | :claude | :codex | :gemini | :pi
  source: :imported,              # :live | :imported
  status: :stopped,               # :starting | :idle | :thinking | :tool_running | :stopped

  # Workspace context
  cwd: "/home/user/project",
  git_root: "/home/user/project",
  branch: "main",

  # Display
  title: "Fix auth bug",
  summary: "# Session summary...",
  model: "claude-sonnet-4",

  # Timing
  started_at: ~U[2026-03-19 09:00:00Z],
  stopped_at: ~U[2026-03-19 10:30:00Z],

  # Origin
  hostname: "workstation",
  agent_version: "1.0.9",

  # Relations (loaded separately)
  turns: [%Turn{}, ...],
  checkpoints: [%Checkpoint{}, ...],
  artifacts: [%Artifact{}, ...],
  todos: [%Todo{}, ...],
  usage: [%Usage{}, ...]
}
```

## Turn

A single exchange unit: one user message followed by one assistant response
(which may contain thinking, text, and tool calls).

```elixir
%Turn{
  index: 0,
  started_at: ~U[2026-03-19 09:01:00Z],

  # User input
  user_message: %UserMessage{
    content: "Fix the login bug",
    attachments: [%Attachment{path: "auth.ex", content: "..."}]
  },

  # Assistant response
  reasoning: "I need to look at the auth module...",
  content: "I found the bug in `verify_token/1`...",
  tool_calls: [%ToolCall{}, ...],

  # Token accounting
  usage: %Usage{
    model: "claude-sonnet-4",
    input_tokens: 15000,
    output_tokens: 3200,
    cache_read_tokens: 12000,
    cache_write_tokens: 0,
    cost: 0.042,
    duration_ms: 8500
  }
}
```

## ToolCall

A single tool invocation with typed arguments and result. The `tool` field
determines which argument/result struct applies.

```elixir
%ToolCall{
  id: "call_abc123",
  tool: :shell,                          # canonical tool type (see below)
  arguments: %Shell.Args{...},          # tool-specific argument struct
  result: %Shell.Result{...},           # tool-specific result struct
  started_at: ~U[2026-03-19 09:01:05Z],
  completed_at: ~U[2026-03-19 09:01:07Z],
  success?: true
}
```

### Tool type atoms

```
:shell | :shell_read | :shell_write | :shell_stop | :shell_list
:file_read | :file_create | :file_edit | :file_patch
:search_content | :search_files
:ask_user
:task_create | :task_read | :task_list
:web_search | :web_fetch
:intent | :todo_update | :sql | :memory | :skill
:github_api
:unknown
```

## Tool argument and result structs

### Shell

```elixir
%Shell.Args{
  command: "mix test --failed",
  workdir: "/home/user/project",
  description: "Run failed tests",
  timeout_ms: 30_000
}

%Shell.Result{
  output: "3 tests, 0 failures",
  exit_status: 0
}
```

### ShellRead (read output from a running shell)

```elixir
%ShellRead.Args{
  session_id: "shell-42",
  timeout_ms: 5000
}

%ShellRead.Result{
  output: "Server started on port 4000"
}
```

### ShellWrite (send input to a running shell)

```elixir
%ShellWrite.Args{
  session_id: "shell-42",
  input: "y\n"
}

%ShellWrite.Result{
  output: "Confirmed. Proceeding..."
}
```

### FileRead

```elixir
%FileRead.Args{
  path: "lib/auth.ex",
  line_range: {10, 25}          # optional, nil = full file
}

%FileRead.Result{
  content: "defmodule Auth do\n  ...",
  size: 1234
}
```

### FileCreate

```elixir
%FileCreate.Args{
  path: "lib/auth/token.ex",
  content: "defmodule Auth.Token do\n  ..."
}

%FileCreate.Result{}            # success is on ToolCall
```

### FileEdit

```elixir
%FileEdit.Args{
  path: "lib/auth.ex",
  old_text: "def verify(token)",
  new_text: "def verify(token, opts \\\\ [])"
}

%FileEdit.Result{}
```

### FilePatch

```elixir
%FilePatch.Args{
  patch: "*** Begin Patch\n*** Update File: lib/auth.ex\n@@...",
  base_path: "/home/user/project"
}

%FilePatch.Result{
  files_changed: ["lib/auth.ex"]
}
```

### SearchContent (grep)

```elixir
%SearchContent.Args{
  pattern: "verify_token",
  path: "lib/",
  file_type: "ex",                # optional
  case_sensitive?: true,
  max_results: 100
}

%SearchContent.Result{
  matches: "lib/auth.ex:42: def verify_token(token)...",
  match_count: 3
}
```

### SearchFiles (glob)

```elixir
%SearchFiles.Args{
  pattern: "lib/**/*.ex",
  path: "/home/user/project"
}

%SearchFiles.Result{
  files: ["lib/auth.ex", "lib/user.ex", ...],
  file_count: 12
}
```

### AskUser

```elixir
%AskUser.Args{
  question: "Which database should I use?",
  choices: ["PostgreSQL (Recommended)", "MySQL", "SQLite"],
  allow_freeform?: true
}

%AskUser.Result{
  response: "PostgreSQL (Recommended)"
}
```

### TaskCreate (sub-agent)

```elixir
%TaskCreate.Args{
  agent_type: "explore",
  name: "find-auth-code",
  description: "Find authentication logic",
  prompt: "Search the codebase for..."
}

%TaskCreate.Result{
  agent_id: "agent-0",
  status: "running"
}
```

### TaskRead (read sub-agent result)

```elixir
%TaskRead.Args{
  agent_id: "agent-0"
}

%TaskRead.Result{
  status: "completed",
  output: "Found authentication in lib/auth/..."
}
```

### WebSearch

```elixir
%WebSearch.Args{
  query: "Elixir Ecto upsert on conflict"
}

%WebSearch.Result{
  content: "According to the Ecto documentation...",
  sources: [%{url: "https://...", title: "..."}]
}
```

### WebFetch

```elixir
%WebFetch.Args{
  url: "https://hexdocs.pm/ecto/Ecto.Repo.html",
  max_length: 5000
}

%WebFetch.Result{
  content: "# Ecto.Repo\n\n...",
  content_type: "text/html"
}
```

### Intent

```elixir
%Intent.Args{
  intent: "Fixing authentication bug"
}

%Intent.Result{}
```

### TodoUpdate

```elixir
%TodoUpdate.Args{
  todo_id: "fix-auth",
  title: "Fix auth token verification",
  status: "done",                # pending | in_progress | done | blocked
  description: "..."
}

%TodoUpdate.Result{}
```

### Sql

```elixir
%Sql.Args{
  query: "SELECT * FROM todos WHERE status = 'pending'",
  database: "session",
  description: "Check pending todos"
}

%Sql.Result{
  rows: [%{"id" => "fix-auth", "status" => "pending"}],
  row_count: 1
}
```

### Memory

```elixir
%Memory.Args{
  subject: "testing practices",
  fact: "Always use start_supervised!/1 in tests",
  reason: "Guarantees cleanup between tests"
}

%Memory.Result{}
```

### GitHubApi

```elixir
%GitHubApi.Args{
  method: "search_code",
  owner: "elixir-lang",
  repo: "elixir",
  query: "defmacro def"
}

%GitHubApi.Result{
  data: %{...}                   # API-specific response
}
```

## Session artifacts

Files and data associated with a session but not part of the conversation flow.

```elixir
%Artifact{
  path: "plan.md",
  artifact_type: :plan,          # :plan | :workspace | :file | :session_db_dump
  content: "# Plan\n\n- Fix auth...",
  content_hash: "a1b2c3...",
  size: 1234
}
```

## Checkpoints

Compaction snapshots preserving context across token limit boundaries.

```elixir
%Checkpoint{
  number: 3,
  title: "After implementing auth module",
  filename: "003-auth-module.md",
  content: "<overview>Implemented JWT verification...</overview>"
}
```

## Todos

Task tracking items extracted from the session.

```elixir
%Todo{
  todo_id: "fix-auth",
  title: "Fix auth token verification",
  description: "The verify_token/1 function doesn't handle expired tokens",
  status: "done",               # pending | in_progress | done | blocked
  depends_on: ["setup-db"]
}
```

## Usage

Token and cost accounting per model invocation.

```elixir
%Usage{
  model: "claude-sonnet-4",
  input_tokens: 15000,
  output_tokens: 3200,
  cache_read_tokens: 12000,
  cache_write_tokens: 0,
  cost: 0.042,
  duration_ms: 8500,
  initiator: "user"             # user | system | compaction
}
```
