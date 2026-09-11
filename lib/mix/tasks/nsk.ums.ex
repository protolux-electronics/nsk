defmodule Mix.Tasks.Nsk.Ums do
  @shortdoc "Loads the USB mass-storage U-Boot onto a board in FEL mode"

  @moduledoc """
  Loads `trellis.bin` from the latest `gworkman/usb_fel_loaders` release onto
  a board that is already in FEL mode and runs it, so the board's storage
  shows up as a USB mass-storage device.

      $ mix nsk.fel
      $ mix nsk.ums

  The loader is cached under `$NERVES_DL_DIR/usb_fel_loaders/<tag>/`
  (`~/.nerves/dl` by default).

  ## Options

    * `--file PATH` - load this file instead of downloading `trellis.bin`
    * `--device SID` - target the FEL device with this SID when several are attached
  """

  use Mix.Task

  alias Nsk.Loader

  @loader "trellis.bin"
  @switches [file: :string, device: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: @switches)
    Mix.Task.run("app.start")

    device = device(opts)
    path = loader_path(opts)

    Mix.shell().info("Loading #{Path.basename(path)} onto #{device.model} (SID #{device.sid})")

    case Sunxi.FEL.execute_uboot(path, device: device, on_progress: &print_progress/1) do
      :ok ->
        IO.write("\n")

        Mix.shell().info(
          "U-Boot running. The board should enumerate as USB mass storage shortly."
        )

      {:error, reason} ->
        IO.write("\n")
        Mix.raise("Failed to load U-Boot: #{inspect(reason)}")
    end
  end

  defp device(opts) do
    case {Sunxi.FEL.list_devices(), Keyword.fetch(opts, :device)} do
      {[device], :error} ->
        device

      {[], _} ->
        Mix.raise("No device in FEL mode found. Run `mix nsk.fel` first.")

      {{:error, reason}, _} ->
        Mix.raise("Could not list FEL devices: #{inspect(reason)}")

      {devices, {:ok, sid}} ->
        Enum.find(devices, &(&1.sid == sid)) ||
          Mix.raise("No FEL device with SID #{sid}. Attached:\n\n#{list_sids(devices)}")

      {devices, :error} ->
        Mix.raise("Several FEL devices found. Pick one with --device:\n\n#{list_sids(devices)}")
    end
  end

  defp list_sids(devices) do
    Enum.map_join(devices, "\n", &"    mix nsk.ums --device #{&1.sid}    (#{&1.model})")
  end

  defp loader_path(opts) do
    case Keyword.fetch(opts, :file) do
      {:ok, path} ->
        File.exists?(path) || Mix.raise("File not found: #{path}")
        path

      :error ->
        fetch_loader()
    end
  end

  defp fetch_loader do
    case Loader.fetch(@loader, on_status: &Mix.shell().info(&1)) do
      {:ok, path} ->
        path

      {:error, :not_cached} ->
        Mix.raise("""
        Could not download #{@loader} and no cached copy exists in #{Loader.cache_dir()}.

        Connect to the internet, or pass a local file with --file.
        """)

      {:error, reason} ->
        Mix.raise("Could not download #{@loader}: #{inspect(reason)}")
    end
  end

  defp print_progress(%{percentage: pct, speed: speed, eta: eta}) do
    filled = div(pct, 4)
    bar = String.duplicate("=", filled) <> String.duplicate(" ", 25 - filled)
    eta = if eta, do: " ETA #{eta}", else: ""
    IO.write("\r[#{bar}] #{String.pad_leading("#{pct}", 3)}% #{speed} kB/s#{eta}   ")
  end
end
