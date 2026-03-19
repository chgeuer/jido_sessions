# JidoSessions

Canonical data model, parsers, and persistence abstractions for coding agent
sessions. Provides a unified way to import, store, query, and export
conversations from GitHub Copilot, Claude Code, Codex, Gemini CLI, and Pi.

## What it does

Coding agents (Copilot, Claude, Codex, Gemini, Pi) each store session history
in different formats — JSONL files, SQLite databases, JSON streams. This library
normalizes them into a shared data model so applications can work with sessions
from any agent identically.

```
Raw agent files          Canonical types              Your application
─────────────────       ──────────────────           ──────────────────
Copilot JSONL    ──┐    Session                     Web UI
Claude sessions  ──┤    ├── Turn                    Session viewer
Codex threads    ──┼──▶ │   ├── ToolCall(:shell)    Handoff export
Gemini events    ──┤    │   ├── ToolCall(:file_edit) Analytics
Pi messages      ──┘    │   └── Usage               Search
                        ├── Artifact
                        ├── Checkpoint
                        └── Todo
```

## Core concepts

### Canonical types

Every session is represented as strongly-typed Elixir structs:

- **`Session`** — root aggregate: agent, cwd, git context, model, timestamps
- **`Turn`** — one user→assistant exchange with reasoning, text, and tool calls
- **`ToolCall`** — typed invocation with canonical tool atom (`:shell`, `:file_edit`, `:search_content`, ...)
  and structured argument/result structs
- **`Artifact`**, **`Checkpoint`**, **`Todo`**, **`Usage`** — supporting data

### Tool canonicalization

50+ agent-specific tool names map to 23 canonical atoms:

```elixir
JidoSessions.ToolNames.canonicalize("Bash")           # => :shell
JidoSessions.ToolNames.canonicalize("shell_command")   # => :shell
JidoSessions.ToolNames.canonicalize("run_shell_command") # => :shell
JidoSessions.ToolNames.canonicalize("Read")            # => :file_read
JidoSessions.ToolNames.canonicalize("view")            # => :file_read
JidoSessions.ToolNames.canonicalize("read_file")       # => :file_read
```

Each tool type has its own argument/result structs:

```elixir
%ToolCall{
  tool: :shell,
  arguments: %Tools.Shell.Args{command: "mix test", workdir: "/project"},
  result: %Tools.Shell.Result{output: "3 tests, 0 failures", exit_status: 0},
  success?: true
}
```

### Two parsing layers

**Agent parsers** read raw files from disk:

```elixir
# Discover and parse session files
sessions = JidoSessions.AgentParsers.Copilot.discover_sessions("~/.copilot/session-state")
{:ok, parsed} = JidoSessions.AgentParsers.Copilot.parse_session("/path/to/session")
# => %{session_id: "abc", events: [...], cwd: "/project", ...}
```

**Event parsers** convert raw events to canonical Turn structs:

```elixir
turns = JidoSessions.parse_turns(raw_events, :copilot)
# => [%Turn{user_content: "Fix the bug", tool_calls: [%ToolCall{tool: :shell, ...}]}]
```

### SessionStore behaviour

Persistence is abstracted behind a behaviour with 15 callbacks:

```elixir
defmodule MyApp.SessionStore do
  @behaviour JidoSessions.SessionStore

  @impl true
  def upsert_session(session), do: # ... your DB logic
  def get_session(id), do: # ...
  def list_sessions(filters), do: # ...
  def insert_events(session_id, events), do: # ...
  # ...
end
```

An in-memory implementation is included for testing:

```elixir
{:ok, store} = JidoSessions.SessionStore.Memory.start_link()
JidoSessions.SessionStore.Memory.upsert_session(store, session)
```

### Sync and watch

Import sessions from disk and watch for changes:

```elixir
# One-shot import
stats = JidoSessions.Sync.import_all(MyStore, nil, agents: agents)

# Continuous watching
{:ok, _} = JidoSessions.Watcher.start_link(
  store_mod: MyStore, store: nil,
  agents: [{:copilot, JidoSessions.AgentParsers.Copilot}]
)
```

### Handoff export

Generate markdown handoff documents for agent-to-agent session transfer:

```elixir
{:ok, %{markdown: md}} = JidoSessions.generate_handoff(MyStore, nil, "session-id",
  full_transcript: true,
  relative_to: "/home/user/project"
)
```

The handoff includes session summary, outstanding work, files read/written,
commands executed, todos, checkpoints, and a chronological transcript.

## Supported agents

| Agent | Disk parser | Event parser | Tool names |
|-------|-------------|--------------|------------|
| GitHub Copilot | ✅ `AgentParsers.Copilot` | ✅ `Parsers.Copilot` | bash, view, edit, grep, glob, ... |
| Claude Code | ✅ `AgentParsers.Claude` | ✅ `Parsers.Claude` | Bash, Read, Write, Edit, Grep, ... |
| Codex | App-provided¹ | ✅ `Parsers.Codex` | shell_command, apply_patch, ... |
| Gemini CLI | ✅ `AgentParsers.Gemini` | ✅ `Parsers.Gemini` | run_shell_command, read_file, ... |
| Pi | App-provided¹ | ✅ `Parsers.Pi` | bash, read, edit, write, ... |

¹ Codex and Pi disk parsers require SDK dependencies (`Exqlite`, `jido_pi`) and
are provided by the host application.

## Installation

```elixir
def deps do
  [
    {:jido_sessions, github: "chgeuer/jido_sessions"}
  ]
end
```

## Module overview

```
JidoSessions                        # Public API: parse_turns/2, generate_handoff/4
├── Session, Turn, ToolCall          # Core data types
├── Tools.*                          # 9 tool arg/result struct modules
├── ToolNames                        # Agent tool name → canonical atom mapping
├── Artifact, Checkpoint, Todo, Usage # Supporting types
├── AgentParser                      # Behaviour for disk-reading parsers
├── AgentParsers.{Copilot,Claude,Gemini} # Disk parser implementations
├── Parsers.{Copilot,Claude,Codex,Gemini,Pi,Helpers} # Event → Turn parsers
├── SessionStore                     # Persistence behaviour (15 callbacks)
├── SessionStore.Memory              # In-memory implementation for testing
├── Sync                             # Discovery + import orchestration
├── Watcher                          # Directory watching GenServer
├── Handoff                          # Markdown export with session resolution
└── Handoff.Extractor                # Turn classifier for files/commands/searches
```

## Related libraries

- **[jido_tool_renderers](https://github.com/chgeuer/jido_tool_renderers)** —
  Phoenix LiveView components for rendering sessions (Rich chat view, Terminal
  view, tool-specific renderers). Uses `jido_sessions` types for the event
  processing pipeline.

## License

MIT


