defmodule SymphonyElixir.CommandTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Command
  alias SymphonyElixir.TestSupport.CommandFixture

  test "returns not found when an executable is absent" do
    original_path = System.get_env("PATH")
    empty_path = Path.join(System.tmp_dir!(), "symphony-empty-path-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(empty_path)
      System.put_env("PATH", empty_path)
      assert {:error, :not_found} = Command.find_executable("symphony-command-does-not-exist")
    after
      restore_env("PATH", original_path)
      File.rm_rf(empty_path)
    end
  end

  test "runs a host fixture with ordered arguments and preserves its exit status" do
    CommandFixture.with_command(
      "command-result",
      """
      #!/bin/sh
      printf 'count:%s args:%s\\n' "$#" "$*"
      exit 7
      """,
      fn _root ->
        assert {:ok, {"count:3 args:first second word third\n", 7}} =
                 Command.run("command-result", ["first", "second word", "third"],
                   stderr_to_stdout: true
                 )
      end
    )
  end

  test "runs a shell command with its nonzero exit status" do
    assert {:ok, {"nope\n", 17}} =
             Command.run("bash", ["-lc", "echo nope && exit 17"], stderr_to_stdout: true)
  end

  test "streams output through a port" do
    assert {:ok, port} = Command.start_port("bash", ["-lc", "printf 'first\\nsecond\\n'"], line: 256)
    assert is_port(port)
    assert_receive {^port, {:data, {:eol, "first"}}}, 1_000
    assert_receive {^port, {:data, {:eol, "second"}}}, 1_000
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
