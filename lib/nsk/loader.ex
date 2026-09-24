defmodule Nsk.Loader do
  @moduledoc """
  Downloads FEL loader binaries from the latest GitHub release of
  `gworkman/usb_fel_loaders` and caches them under the Nerves download
  directory (`$NERVES_DL_DIR`, defaulting to `~/.nerves/dl`).

  Files are cached per release tag, so a new release is picked up on the
  next run and older downloads are never overwritten.
  """

  @repo "gworkman/usb_fel_loaders"
  @latest_release_url "https://api.github.com/repos/#{@repo}/releases/latest"

  @doc """
  Returns the local path of the named release asset, downloading it if needed.

  When GitHub cannot be reached, the newest cached copy is used instead.

  ## Options

    * `:on_status` - a 1-arity function called with progress messages.
      Defaults to a no-op.
  """
  @spec fetch(String.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def fetch(name, opts \\ []) do
    ensure_req_started!()
    on_status = Keyword.get(opts, :on_status, fn _msg -> :ok end)

    case latest_release(name) do
      {:ok, tag, url} ->
        ensure_cached(name, tag, url, on_status)

      {:error, reason} ->
        on_status.("Could not reach GitHub (#{describe(reason)}), using cached copy")
        newest_cached(name)
    end
  end

  @doc """
  The directory in which loaders are cached.
  """
  @spec cache_dir() :: Path.t()
  def cache_dir do
    base = System.get_env("NERVES_DL_DIR") || Path.join(System.user_home!(), ".nerves/dl")
    Path.join(base, "usb_fel_loaders")
  end

  # `Mix.Task.run("app.start")` is not enough. The README has people depend on
  # this with `runtime: false`, which keeps `:nsk` and everything under it out of
  # the application list — so `app.start` starts neither `:req` nor the `:finch`
  # underneath it, and the first request fails with `unknown registry:
  # Req.Finch` from inside Finch's pool manager.
  defp ensure_req_started! do
    case Application.ensure_all_started(:req) do
      {:ok, _apps} ->
        :ok

      {:error, reason} ->
        raise "could not start :req to download the loader: #{inspect(reason)}"
    end
  end

  defp latest_release(name) do
    with {:ok, %{status: 200, body: release}} <- Req.get(@latest_release_url),
         %{"tag_name" => tag, "assets" => assets} <- release,
         %{"browser_download_url" => url} <- Enum.find(assets, &(&1["name"] == name)) do
      {:ok, tag, url}
    else
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
      nil -> {:error, {:asset_missing, name}}
      _ -> {:error, :unexpected_response}
    end
  end

  defp ensure_cached(name, tag, url, on_status) do
    path = Path.join([cache_dir(), tag, name])

    if File.exists?(path) do
      on_status.("Using cached #{name} (#{tag})")
      {:ok, path}
    else
      on_status.("Downloading #{name} (#{tag})...")
      download(url, path)
    end
  end

  # Download to a sibling temp file and rename so a partial download is
  # never mistaken for a cached loader.
  defp download(url, path) do
    tmp = path <> ".part"
    File.mkdir_p!(Path.dirname(path))

    case Req.get(url, into: File.stream!(tmp)) do
      {:ok, %{status: 200}} ->
        File.rename!(tmp, path)
        {:ok, path}

      {:ok, %{status: status}} ->
        File.rm(tmp)
        {:error, {:http_status, status}}

      {:error, reason} ->
        File.rm(tmp)
        {:error, reason}
    end
  end

  defp newest_cached(name) do
    cache_dir()
    |> Path.join("*/#{name}")
    |> Path.wildcard()
    |> Enum.sort_by(
      &Version.parse!(String.trim_leading(Path.basename(Path.dirname(&1)), "v")),
      {:desc, Version}
    )
    |> case do
      [path | _] -> {:ok, path}
      [] -> {:error, :not_cached}
    end
  end

  defp describe({:http_status, status}), do: "HTTP #{status}"
  defp describe(%{__exception__: true} = e), do: Exception.message(e)
  defp describe(reason), do: inspect(reason)
end
