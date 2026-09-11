defmodule Mix.Tasks.Nsk.Fel do
  @shortdoc "Puts the board into FEL mode via the CH340 DTR/RTS lines"

  @moduledoc """
  Resets an attached Allwinner board into FEL (USB bootloader) mode.

  Finds the CH340 USB-serial adapter (VID 0x1A86, PID 0x7523), toggles its
  DTR (RESET) and RTS (BOOT) lines in bootloader order, then waits for the
  board to show up as a FEL USB device.

      $ mix nsk.fel

  ## Options

    * `--port NAME` - use this serial port instead of auto-detecting the CH340
    * `--no-verify` - skip waiting for the FEL device to appear
    * `--timeout MS` - how long to wait for the FEL device (default 3000)
  """

  use Mix.Task

  alias Nsk.FEL

  @switches [port: :string, verify: :boolean, timeout: :integer]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: @switches)
    Mix.Task.run("app.start")

    port = port(opts)
    Mix.shell().info("Using #{port}")

    case FEL.enter(port, on_step: &Mix.shell().info(&1)) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("Failed to reset the board: #{describe(reason)}")
    end

    if Keyword.get(opts, :verify, true) do
      verify(Keyword.get(opts, :timeout, 3_000))
    else
      Mix.shell().info("Done. The board should now be in FEL mode.")
    end
  end

  defp port(opts) do
    case Keyword.fetch(opts, :port) do
      {:ok, port} -> port
      :error -> detect_port()
    end
  end

  defp detect_port do
    case FEL.find_ch340() do
      {:ok, port} ->
        port

      {:error, :not_found} ->
        Mix.raise("""
        No CH340 adapter found.

        Check that the board is plugged in, or pass the port explicitly:

            mix nsk.fel --port cu.wchusbserialXXXX
        """)

      {:error, {:multiple, ports}} ->
        Mix.raise("""
        Several CH340 adapters found. Pick one with --port:

        #{Enum.map_join(ports, "\n", &("    mix nsk.fel --port " <> &1))}
        """)
    end
  end

  defp verify(timeout) do
    Mix.shell().info("Waiting for FEL device...")

    case FEL.wait_for_device(timeout: timeout) do
      {:ok, %{model: model, sid: sid}} ->
        Mix.shell().info("Done. FEL device ready: #{model} (SID #{sid})")

      {:error, :timeout} ->
        Mix.raise("""
        The board did not show up as a FEL USB device within #{timeout} ms.

        Check the USB OTG cable and the BOOT/RESET wiring to RTS/DTR.
        """)
    end
  end

  defp describe({:open, reason}), do: "could not open port (#{inspect(reason)})"
  defp describe({signal, reason}), do: "could not set #{signal} (#{inspect(reason)})"
end
