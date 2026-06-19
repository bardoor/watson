defmodule Watson.Audio.WavWriter do
  @moduledoc false

  use GenServer

  @header_size 44

  defstruct [
    :path,
    :handle,
    :sample_rate,
    :channels,
    data_size: 0
  ]

  @type t() :: %__MODULE__{
          path: String.t(),
          handle: :file.io_device(),
          sample_rate: pos_integer(),
          channels: pos_integer(),
          data_size: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec append(pid(), binary()) :: :ok
  def append(pid, pcm) do
    GenServer.call(pid, {:append, pcm}, :infinity)
  end

  @spec snapshot(pid(), String.t()) :: :ok | {:error, term()}
  def snapshot(pid, snapshot_path) do
    GenServer.call(pid, {:snapshot, snapshot_path}, :infinity)
  end

  @spec finalize(pid()) :: {:ok, %{path: String.t(), data_size: non_neg_integer()}} | {:error, term()}
  def finalize(pid) do
    GenServer.call(pid, :finalize, :infinity)
  end

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    sample_rate = Keyword.fetch!(opts, :sample_rate)
    channels = Keyword.fetch!(opts, :channels)

    with {:ok, handle} <- :file.open(String.to_charlist(path), [:binary, :write]),
         :ok <- :file.write(handle, zero_header()) do
      {:ok, %__MODULE__{path: path, handle: handle, sample_rate: sample_rate, channels: channels}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:append, pcm}, _from, state) do
    case :file.write(state.handle, pcm) do
      :ok ->
        {:reply, :ok, %{state | data_size: state.data_size + byte_size(pcm)}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:snapshot, snapshot_path}, _from, state) do
    with :ok <- :file.sync(state.handle),
         :ok <- File.cp(state.path, snapshot_path),
         :ok <- write_header(snapshot_path, state.sample_rate, state.channels, state.data_size) do
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:finalize, _from, state) do
    result =
      with :ok <- :file.sync(state.handle),
           :ok <- write_header(state.path, state.sample_rate, state.channels, state.data_size),
           :ok <- :file.close(state.handle) do
        {:ok, %{path: state.path, data_size: state.data_size}}
      end

    {:stop, :normal, result, state}
  end

  defp zero_header do
    :binary.copy(<<0>>, @header_size)
  end

  defp write_header(path, sample_rate, channels, data_size) do
    block_align = channels * 2
    byte_rate = sample_rate * block_align
    riff_size = 36 + data_size

    header =
      <<
        "RIFF",
        riff_size::little-32,
        "WAVE",
        "fmt ",
        16::little-32,
        1::little-16,
        channels::little-16,
        sample_rate::little-32,
        byte_rate::little-32,
        block_align::little-16,
        16::little-16,
        "data",
        data_size::little-32
      >>

    case :file.open(String.to_charlist(path), [:binary, :read, :write]) do
      {:ok, handle} ->
        with :ok <- :file.pwrite(handle, 0, header),
             :ok <- :file.close(handle) do
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
