defmodule SymphonyElixir.Command do
  @moduledoc false

  @type result :: {:ok, {String.t(), non_neg_integer()}} | {:error, term()}

  @spec find_executable(String.t()) :: {:ok, Path.t()} | {:error, :not_found}
  def find_executable(command) when is_binary(command) do
    case System.find_executable(command) || existing_path(command) || shell_fallback(command) do
      nil -> {:error, :not_found}
      executable -> {:ok, executable}
    end
  end

  @spec run(String.t(), [String.t()], keyword()) :: result()
  def run(command, args, opts \\ []) when is_binary(command) and is_list(args) and is_list(opts) do
    with {:ok, executable} <- find_executable(command) do
      {program, program_args} = invocation(executable, args)

      try do
        {:ok, System.cmd(program, program_args, opts)}
      rescue
        error in ErlangError -> {:error, error.original}
      end
    end
  end

  @spec start_port(String.t(), [String.t()], keyword()) :: {:ok, port()} | {:error, term()}
  def start_port(command, args, opts \\ []) when is_binary(command) and is_list(args) and is_list(opts) do
    with {:ok, executable} <- find_executable(command) do
      try do
        case windows_batch?(executable) do
          true -> open_windows_batch_port(executable, args, opts)
          false -> {:ok, open_native_port(executable, args, opts)}
        end
      rescue
        error -> {:error, error}
      end
    end
  end

  defp existing_path(command) do
    if File.regular?(command), do: command, else: nil
  end

  defp shell_fallback(command) when command in ["bash", "sh"] do
    case :os.type() do
      {:win32, _} ->
        candidate = Path.join([System.get_env("ProgramFiles") || "C:/Program Files", "Git", "bin", "bash.exe"])
        if File.regular?(candidate), do: candidate, else: nil

      _ ->
        nil
    end
  end

  defp shell_fallback(_command), do: nil

  defp invocation(executable, args) do
    if windows_batch?(executable) do
      {command_processor(), ["/d", "/c", executable | args]}
    else
      {executable, args}
    end
  end

  defp windows_batch?(executable) do
    case :os.type() do
      {:win32, _} -> String.downcase(Path.extname(executable)) in [".bat", ".cmd"]
      _ -> false
    end
  end

  defp command_processor do
    System.get_env("COMSPEC") || System.find_executable("cmd") || "cmd.exe"
  end

  defp normalize_port_opts(opts) do
    Enum.map(opts, fn
      {:cd, path} when is_binary(path) -> {:cd, String.to_charlist(path)}
      other -> other
    end)
  end

  defp open_native_port(program, args, opts) do
    port_opts =
      port_defaults(args)
      |> Kernel.++(normalize_port_opts(opts))

    Port.open({:spawn_executable, String.to_charlist(program)}, port_opts)
  end

  defp open_windows_batch_port(executable, args, opts) do
    {:ok, open_native_port(command_processor(), ["/d", "/c", executable | args], opts)}
  end

  defp port_defaults(args) do
    defaults = [:binary, :exit_status, :stderr_to_stdout, args: Enum.map(args, &String.to_charlist/1)]

    case :os.type() do
      {:win32, _} -> [:use_stdio | defaults]
      _ -> defaults
    end
  end
end
