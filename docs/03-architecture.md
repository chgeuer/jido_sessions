# Architecture: jido_sessions

How jido_sessions fits between the agent CLIs (source of raw data) and the
consuming applications (web UI, export tools, analytics).

## Library boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│  Agent CLIs (external binaries / SDKs)                         │
│  Copilot CLI · Claude Code · Codex CLI · Gemini CLI · Pi CLI  │
└──────────┬──────────────────────────────────────────────────────┘
           │ raw events (JSONL, SQLite, JSON streams)
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  jido_sessions                                                  │
│                                                                 │
│  ┌─────────────┐   ┌──────────────┐   ┌──────────────────────┐ │
│  │ Parsers     │   │ Canonical    │   │ SessionStore         │ │
│  │             │──▶│ Types        │──▶│ (behaviour)          │ │
│  │ • Copilot   │   │              │   │                      │ │
│  │ • Claude    │   │ • Session    │   │ • upsert_session/1   │ │
│  │ • Codex     │   │ • Turn       │   │ • insert_events/2    │ │
│  │ • Gemini    │   │ • ToolCall   │   │ • get_session/1      │ │
│  │ • Pi        │   │ • Artifact   │   │ • list_sessions/1    │ │
│  └─────────────┘   │ • Checkpoint │   │ • upsert_artifact/2  │ │
│                     │ • Todo       │   │ • ...                │ │
│  ┌─────────────┐   │ • Usage      │   └──────────────────────┘ │
│  │ Sync Engine │   └──────────────┘              ▲             │
│  │ • discover  │          │                      │             │
│  │ • import    │──────────┘                      │             │
│  │ • watch     │                                 │             │
│  └─────────────┘                                 │             │
│                                                  │             │
│  ┌─────────────┐                                 │             │
│  │ Handoff     │   reads from store ─────────────┘             │
│  │ • export    │                                               │
│  │ • markdown  │                                               │
│  └─────────────┘                                               │
└─────────────────────────────────────────────────────────────────┘
           │ implements SessionStore behaviour
           ▼
┌─────────────────────────────────────────────────────────────────┐
│  copilot_lv (Phoenix app)                                       │
│                                                                 │
│  • Ash resources (Session, Event, ...) with AshPostgres/SQLite  │
│  • SessionStore implementation (Ash queries + bulk inserts)      │
│  • LiveViews (session list, session viewer, sync page)          │
│  • SessionServer (live CLI connection, PubSub broadcasts)       │
│  • AskUserBroker (interactive tool request handling)            │
└─────────────────────────────────────────────────────────────────┘
```

## What lives where

### In jido_sessions (the library)

| Module | Purpose |
|--------|---------|
| `JidoSessions.Session` | Session struct |
| `JidoSessions.Turn` | Turn struct (user message + assistant response) |
| `JidoSessions.ToolCall` | Tool invocation with typed args/result |
| `JidoSessions.Tools.*` | Per-tool argument and result structs (Shell, FileRead, etc.) |
| `JidoSessions.Artifact` | Session artifact struct |
| `JidoSessions.Checkpoint` | Compaction checkpoint struct |
| `JidoSessions.Todo` | Task tracking item struct |
| `JidoSessions.Usage` | Token/cost accounting struct |
| `JidoSessions.SessionStore` | Behaviour for persistence backends |
| `JidoSessions.Parsers.Copilot` | Raw Copilot events → canonical types |
| `JidoSessions.Parsers.Claude` | Raw Claude events → canonical types |
| `JidoSessions.Parsers.Codex` | Raw Codex events → canonical types |
| `JidoSessions.Parsers.Gemini` | Raw Gemini events → canonical types |
| `JidoSessions.Parsers.Pi` | Raw Pi events → canonical types |
| `JidoSessions.Sync` | Discovery + import orchestration |
| `JidoSessions.Watcher` | Directory watching (inotify + polling) |
| `JidoSessions.Handoff` | Export to markdown |
| `JidoSessions.Handoff.Extractor` | Extract prompts/operations from turns |

### In copilot_lv (the app)

| Module | Purpose |
|--------|---------|
| `CopilotLv.Sessions.*` | Ash resource definitions (DB schema) |
| `CopilotLv.SessionStoreImpl` | `SessionStore` behaviour implementation using Ash |
| `CopilotLv.Repo` | Ecto/Ash repo (SQLite or Postgres) |
| `CopilotLv.SessionServer` | GenServer for live CLI connections |
| `CopilotLv.AskUserBroker` | Bridges ask_user tool calls to LiveView |
| `CopilotLvWeb.SessionLive.*` | LiveView pages |

## SessionStore behaviour

The central abstraction that decouples jido_sessions from any specific database.

```elixir
defmodule JidoSessions.SessionStore do
  @callback upsert_session(Session.t()) ::
              {:ok, Session.t()} | {:error, term()}

  @callback get_session(String.t()) ::
              {:ok, Session.t()} | {:error, :not_found}

  @callback list_sessions(keyword()) ::
              [Session.t()]

  @callback delete_session(String.t()) ::
              :ok | {:error, term()}

  @callback insert_events(String.t(), [map()]) ::
              {:ok, non_neg_integer()}

  @callback get_events(String.t()) ::
              [map()]

  @callback upsert_artifacts(String.t(), [Artifact.t()]) ::
              :ok

  @callback upsert_todos(String.t(), [Todo.t()]) ::
              :ok

  @callback insert_checkpoints(String.t(), [Checkpoint.t()]) ::
              :ok

  @callback insert_usage(String.t(), [Usage.t()]) ::
              :ok

  @callback session_exists?(String.t()) ::
              boolean()
end
```

## Data flow: import

```
1. Watcher detects new/changed files in well-known directories
     │
2. Sync.discover(agent, base_dir)
     │  returns [{session_id, path}]
     │
3. Parsers.Copilot.parse(path)  (or Claude, Codex, etc.)
     │  reads raw files (JSONL, SQLite, JSON)
     │  returns %Session{turns: [...], artifacts: [...], ...}
     │
4. Sync.import(session, store)
     │  calls store.upsert_session(session)
     │  calls store.insert_events(session.id, raw_events)
     │  calls store.upsert_artifacts(session.id, artifacts)
     │  calls store.upsert_todos(session.id, todos)
     │  calls store.insert_checkpoints(session.id, checkpoints)
     │  returns {:ok, stats}
```

## Data flow: export / handoff

```
1. Handoff.generate(session_id, store)
     │
2. store.get_session(session_id)
   store.get_events(session_id)
   store.get_artifacts(session_id)
     │
3. Extractor.extract(session, events)
     │  classifies tool calls by type
     │  groups into prompts + operations
     │  identifies pending work
     │
4. Handoff.render_markdown(extracted_data)
     │  returns markdown string
```

## Data flow: live session (stays in app)

```
1. User clicks "New Session" in LiveView
     │
2. SessionServer.start(model, cwd)
     │  connects to agent CLI via SDK
     │
3. User sends prompt via LiveView
     │  SessionServer.send_prompt(text)
     │
4. Agent streams events
     │  SessionServer broadcasts via PubSub
     │  SessionServer persists via SessionStore
     │
5. LiveView receives events
     │  Accumulator.process_event(acc, type, data)
     │  stream_insert into UI
```

## Database adapter considerations

The `SessionStore` behaviour is intentionally database-agnostic. Implementations
can optimize for their backend:

| Operation | SQLite optimization | Postgres optimization |
|-----------|--------------------|-----------------------|
| Bulk event insert | `Exqlite` `insert_all` with chunking | `COPY` or multi-row `INSERT` |
| Upsert artifacts | `ON CONFLICT DO UPDATE` | `ON CONFLICT DO UPDATE` |
| Event ordering | `ORDER BY sequence` | `ORDER BY sequence` |
| Full-text search | External FTS5 table | `tsvector` + GIN index |
| JSON querying | `json_extract` | `jsonb` operators |

The struct types in jido_sessions carry no database annotations — they're plain
Elixir structs. The app's Ash resources (or Ecto schemas) define the actual
database mapping and can use whichever adapter they want.
