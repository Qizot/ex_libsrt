defmodule ExLibSRT.SRTLiveTransmit do
  @moduledoc """
  Wrapper around `srt-live-transmit` executable that is able to take
  an arbitrary binary payload and run a system process to stream it.
  """

  @opaque streaming_proxy :: port()
  @opaque stream :: :gen_udp.socket()

  @spec start_streaming_proxy(non_neg_integer(), non_neg_integer(), binary()) :: streaming_proxy()
  def start_streaming_proxy(udp_port, srt_port, stream_id \\ "") do
    args = [
      :binary,
      {:args,
       [
         "-q",
         "-loglevel:fatal",
         "-autoreconnect:no",
         "udp://127.0.0.1:#{udp_port}",
         "srt://127.0.0.1:#{srt_port}?streamid=#{stream_id}"
       ]}
    ]

    port = Port.open({:spawn_executable, System.find_executable("srt-live-transmit")}, args)

    wait_for_port(udp_port)

    port
  end

  @spec stop_proxy(streaming_proxy()) :: :ok
  def stop_proxy(proxy) do
    {:os_pid, os_pid} = :erlang.port_info(proxy, :os_pid)
    {_reuslt, 0} = System.cmd("kill", ["-15", "#{os_pid}"])

    :ok
  end

  @spec start_stream(non_neg_integer()) :: stream()
  def start_stream(udp_port) do
    {:ok, socket} = :gen_udp.open(0, [:binary])

    :ok = :gen_udp.connect(socket, ~c"127.0.0.1", udp_port)

    socket
  end

  @spec send_payload(stream(), binary()) :: :ok
  def send_payload(socket, payload) do
    :gen_udp.send(socket, payload)

    :ok
  end

  @chunk_size 1_000
  @spec send_file(stream(), Path.t()) :: :ok
  def send_file(socket, path) do
    file = File.open!(path, [:binary, :read])

    {:ok, %File.Stat{size: size}} = File.stat(path)

    chunks = div(size, @chunk_size)
    remaining = rem(size, @chunk_size)

    Enum.each(1..chunks, fn _i ->
      payload = IO.read(file, @chunk_size)

      send_payload(socket, payload)
    end)

    if remaining > 0 do
      payload = IO.read(file, remaining)

      send_payload(socket, payload)
    end

    File.close(file)

    :ok
  end

  @spec close_stream(stream()) :: :ok
  def close_stream(socket) do
    :gen_udp.close(socket)

    :ok
  end

  defp wait_for_port(port, retries \\ 3)

  defp wait_for_port(_port, 0), do: {:error, :port_not_active}

  defp wait_for_port(port, retries) do
    case :gen_udp.open(port, [:binary]) do
      {:ok, socket} ->
        :gen_udp.close(socket)

        Process.sleep(trunc(:math.pow(2, 3 - retries) * 100))

        wait_for_port(port, retries - 1)

      {:error, :eaddrinuse} ->
        :ok
    end
  end
end
