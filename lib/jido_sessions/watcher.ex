defmodule JidoSessions.Watcher do
  @moduledoc """
  GenServer watching agent session directories for new/changed sessions.

  Combines filesystem notifications (via FileSystem/inotify) with periodic
  polling to discover new sessions and trigger imports.

  ## Usage

      {:ok, _pid} = Watcher.start_link(
        store_mod: MyApp.SessionStore,
        store: MyApp.Repo,
        agents: [{:copilot, MyApp.Agents.Copilot}],
        poll_interval: :timer.seconds(30)
      )
  """

  use GenServer

  require Logger

  @default_poll_interval :timer.seconds(30)
  @debounce_interval :timer.seconds(2)

  defstruct [
    :store_mod,
    :store,
    :agents,
    :poll_interval,
    :fs_pid,
    :callback,
    pending_dirs: MapSet.new(),
    debounce_ref: nil
  ]

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      store_mod: Keyword.fetch!(opts, :store_mod),
      store: Keyword.fetch!(opts, :store),
      agents: Keyword.get(opts, :agents, []),
      poll_interval: Keyword.get(opts, :poll_interval, @default_poll_interval),
      callback: Keyword.get(opts, :callback)
    }

    fs_pid = start_fs_watcher(state.agents)
    state = %{state | fs_pid: fs_pid}

    Process.send_after(self(), :poll, 1_000)

    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    do_sync(state)
    Process.send_after(self(), :poll, state.poll_interval)
    {:noreply, state}
  end

  def handle_info({:file_event, _pid, {path, _events}}, state) do
    dir = if File.dir?(path), do: path, else: Path.dirname(path)
    pending = MapSet.put(state.pending_dirs, dir)
    state = %{state | pending_dirs: pending}

    if state.debounce_ref, do: Process.cancel_timer(state.debounce_ref)
    ref = Process.send_after(self(), :debounced_sync, @debounce_interval)

    {:noreply, %{state | debounce_ref: ref}}
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    Logger.warning("[Watcher] FileSystem stopped")
    {:noreply, %{state | fs_pid: nil}}
  end

  def handle_info(:debounced_sync, state) do
    if MapSet.size(state.pending_dirs) > 0 do
      do_sync(state)
    end

    {:noreply, %{state | pending_dirs: MapSet.new(), debounce_ref: nil}}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp do_sync(state) do
    stats =
      JidoSessions.Sync.import_all(state.store_mod, state.store, agents: state.agents)

    if stats.imported > 0 || stats.updated > 0 do
      Logger.info(
        "[Watcher] Sync: #{stats.imported} imported, #{stats.updated} updated, #{stats.skipped} skipped"
      )

      if state.callback, do: state.callback.(stats)
    end
  end

  defp start_fs_watcher(agents) do
    dirs =
      agents
      |> Enum.flat_map(fn {_atom, mod} ->
        if function_exported?(mod, :well_known_dirs, 0) do
          mod.well_known_dirs() |> Enum.filter(&File.dir?/1)
        else
          []
        end
      end)

    fs_mod = Module.concat([:FileSystem])

    if dirs != [] && Code.ensure_loaded?(fs_mod) do
      case apply(fs_mod, :start_link, [[dirs: dirs]]) do
        {:ok, pid} ->
          apply(fs_mod, :subscribe, [pid])
          pid

        {:error, reason} ->
          Logger.warning("[Watcher] FileSystem start failed: #{inspect(reason)}")
          nil
      end
    else
      nil
    end
  end
end
