defmodule Nsk.FEL do
  @moduledoc """
  Puts an Allwinner board into FEL (USB bootloader) mode over a CH340
  USB-serial adapter whose DTR and RTS lines are wired to RESET and BOOT.
  """

  @ch340_vendor_id 0x1A86
  @ch340_product_id 0x7522

  # Each step sets the listed signals and then holds them for `hold` ms.
  # Both signals are active-low on the board: `set_dtr(true)` pulls RESET low,
  # `set_rts(true)` pulls BOOT low.
  @sequence [
    {"Idle (BOOT and RESET released)", [dtr: false, rts: false], 100},
    {"Asserting BOOT", [rts: true], 100},
    {"Asserting RESET", [dtr: true], 200},
    {"Releasing RESET (BOOT still held)", [dtr: false], 500},
    {"Releasing BOOT", [rts: false], 0}
  ]

  @doc """
  Finds the serial port backed by a CH340 adapter.

  `ports` defaults to `Circuits.UART.enumerate/0` and has the same shape.

  Returns `{:ok, port_name}`, `{:error, :not_found}`, or
  `{:error, {:multiple, port_names}}` when more than one CH340 is attached.
  """
  @spec find_ch340(map()) :: {:ok, String.t()} | {:error, :not_found | {:multiple, [String.t()]}}
  def find_ch340(ports \\ Circuits.UART.enumerate()) do
    ports
    |> Enum.filter(fn {_name, info} -> is_ch340?(info[:vendor_id], info[:product_id]) end)
    |> Enum.map(fn {name, _info} -> name end)
    |> Enum.sort()
    |> case do
      [name] -> {:ok, name}
      [] -> {:error, :not_found}
      names -> {:error, {:multiple, names}}
    end
  end

  def is_ch340?(@ch340_vendor_id, @ch340_product_id), do: true
  def is_ch340?(_vid, _pid), do: false

  @doc """
  Runs the BOOT/RESET sequence on `port` to drop the board into FEL mode.

  ## Options

    * `:on_step` - a 1-arity function called with a description of each step
      as it starts. Defaults to a no-op.

  The port is always released, even if a step fails.
  """
  @spec enter(String.t(), keyword()) :: :ok | {:error, term()}
  def enter(port, opts \\ []) do
    on_step = Keyword.get(opts, :on_step, fn _label -> :ok end)
    {:ok, uart} = Circuits.UART.start_link()

    try do
      with :ok <- open(uart, port) do
        run_sequence(uart, on_step)
      end
    after
      Circuits.UART.stop(uart)
    end
  end

  defp open(uart, port) do
    case Circuits.UART.open(uart, port, speed: 115_200, active: false) do
      :ok -> :ok
      {:error, reason} -> {:error, {:open, reason}}
    end
  end

  defp run_sequence(uart, on_step) do
    Enum.reduce_while(@sequence, :ok, fn {label, signals, hold}, :ok ->
      on_step.(label)

      case set_signals(uart, signals) do
        :ok ->
          Process.sleep(hold)
          {:cont, :ok}

        error ->
          {:halt, error}
      end
    end)
  end

  defp set_signals(uart, signals) do
    Enum.reduce_while(signals, :ok, fn {signal, value}, :ok ->
      case set_signal(uart, signal, value) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {signal, reason}}}
      end
    end)
  end

  defp set_signal(uart, :dtr, value), do: Circuits.UART.set_dtr(uart, value)
  defp set_signal(uart, :rts, value), do: Circuits.UART.set_rts(uart, value)

  @doc """
  Polls `Sunxi.FEL.list_devices/0` until a device appears.

  ## Options

    * `:timeout` - how long to keep polling, in ms. Defaults to 3000.
    * `:interval` - delay between polls, in ms. Defaults to 200.
  """
  @spec wait_for_device(keyword()) :: {:ok, Sunxi.Device.t()} | {:error, :timeout}
  def wait_for_device(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 3_000)
    interval = Keyword.get(opts, :interval, 200)
    deadline = System.monotonic_time(:millisecond) + timeout

    poll_device(deadline, interval)
  end

  defp poll_device(deadline, interval) do
    case Sunxi.FEL.list_devices() do
      [device | _rest] ->
        {:ok, device}

      _none_or_error ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(interval)
          poll_device(deadline, interval)
        end
    end
  end
end
