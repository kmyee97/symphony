defmodule SymphonyElixir.TestSupport.CommandFixture do
  @moduledoc false

  @spec with_command(String.t(), String.t(), (Path.t() -> term())) :: term()
  def with_command(name, script, fun) when is_binary(name) and is_binary(script) and is_function(fun, 1) do
    root = Path.join(System.tmp_dir!(), "symphony-command-fixture-#{System.unique_integer([:positive])}")
    bin_dir = Path.join(root, "bin")
    original_path = System.get_env("PATH")

    try do
      File.mkdir_p!(bin_dir)
      install_command!(bin_dir, name, script)
      System.put_env("PATH", join_path([bin_dir, original_path || ""]))
      fun.(root)
    after
      restore_env("PATH", original_path)
      File.rm_rf(root)
    end
  end

  @spec install_command!(Path.t(), String.t(), String.t()) :: Path.t()
  def install_command!(bin_dir, name, script)
      when is_binary(bin_dir) and is_binary(name) and is_binary(script) do
    case :os.type() do
      {:win32, _} ->
        install_windows_command!(bin_dir, name, script)

      _ ->
        path = Path.join(bin_dir, name)
        File.write!(path, script)
        File.chmod!(path, 0o755)
        path
    end
  end

  @spec install_port_command!(Path.t(), String.t(), String.t()) :: Path.t()
  def install_port_command!(bin_dir, name, script)
      when is_binary(bin_dir) and is_binary(name) and is_binary(script) do
    case :os.type() do
      {:win32, _} -> install_windows_port_command!(bin_dir, name, script)
      _ -> install_command!(bin_dir, name, script)
    end
  end

  @spec join_path([String.t()]) :: String.t()
  def join_path(paths) do
    paths
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(path_separator())
  end

  @spec path_separator() :: String.t()
  def path_separator do
    case :os.type() do
      {:win32, _} -> ";"
      _ -> ":"
    end
  end

  defp install_windows_command!(bin_dir, name, script) do
    shell_path = Path.join(bin_dir, "#{name}.sh")
    wrapper_path = Path.join(bin_dir, "#{name}.cmd")
    git_bash = Path.join([System.get_env("ProgramFiles") || "C:/Program Files", "Git", "bin", "bash.exe"])

    File.write!(shell_path, normalize_newlines(script))

    File.write!(wrapper_path, "@echo off\r\n\"#{git_bash}\" \"%~dp0#{name}.sh\" %*\r\n")
    wrapper_path
  end

  defp install_windows_port_command!(bin_dir, name, script) do
    shell_path = Path.join(bin_dir, "#{name}.sh")
    source_path = Path.join(bin_dir, "#{name}.cs")
    executable_path = Path.join(bin_dir, "#{name}.exe")
    git_bash = Path.join([System.get_env("ProgramFiles") || "C:/Program Files", "Git", "bin", "bash.exe"])

    File.write!(shell_path, normalize_newlines(script))

    File.write!(source_path, """
    using System;
    using System.Diagnostics;
    using System.IO;

    class FixtureProxy
    {
      static string Quote(string value) { return "\\\"" + value.Replace("\\\"", "\\\\\\\"") + "\\\""; }

      static int Main(string[] args)
      {
        var process = new Process();
        process.StartInfo.FileName = @"#{git_bash}";
        process.StartInfo.Arguments = Quote(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "#{name}.sh")) + " " + String.Join(" ", Array.ConvertAll(args, Quote));
        process.StartInfo.UseShellExecute = false;
        process.Start();
        process.WaitForExit();
        return process.ExitCode;
      }
    }
    """)

    case System.cmd(csharp_compiler(), [
           "/nologo",
           "/target:exe",
           "/out:#{windows_native_path(executable_path)}",
           windows_native_path(source_path)
         ]) do
      {_, 0} -> executable_path
      {output, status} -> raise "failed to compile native command fixture (#{status}): #{output}"
    end
  end

  defp csharp_compiler do
    Path.join([System.get_env("WINDIR") || "C:/Windows", "Microsoft.NET", "Framework64", "v4.0.30319", "csc.exe"])
  end

  defp windows_native_path(path), do: String.replace(path, "/", "\\")

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp normalize_newlines(content) do
    content
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
  end
end
