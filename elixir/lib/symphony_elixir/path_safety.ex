defmodule SymphonyElixir.PathSafety do
  @moduledoc false

  @type canonical_descendant_error ::
          :workspace_root
          | {:outside_workspace_root, Path.t(), Path.t()}
          | {:symlink_escape, Path.t(), Path.t()}
          | {:path_canonicalize_failed, Path.t(), term()}

  @spec canonicalize(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def canonicalize(path) when is_binary(path) do
    expanded_path = Path.expand(path)
    {root, segments} = split_absolute_path(expanded_path)

    case resolve_segments(root, [], segments) do
      {:ok, canonical_path} ->
        {:ok, canonical_path}

      {:error, reason} ->
        {:error, {:path_canonicalize_failed, expanded_path, reason}}
    end
  end

  @spec canonical_descendant(Path.t(), Path.t()) ::
          {:ok, Path.t()} | {:error, canonical_descendant_error()}
  def canonical_descendant(candidate, root) when is_binary(candidate) and is_binary(root) do
    expanded_candidate = Path.expand(candidate)
    expanded_root = Path.expand(root)

    with {:ok, canonical_candidate} <- canonicalize(expanded_candidate),
         {:ok, canonical_root} <- canonicalize(expanded_root) do
      cond do
        canonical_candidate == canonical_root ->
          {:error, :workspace_root}

        descendant_path?(canonical_candidate, canonical_root) ->
          {:ok, canonical_candidate}

        descendant_path?(expanded_candidate, expanded_root) ->
          {:error, {:symlink_escape, expanded_candidate, canonical_root}}

        true ->
          {:error, {:outside_workspace_root, canonical_candidate, canonical_root}}
      end
    end
  end

  defp split_absolute_path(path) when is_binary(path) do
    [root | segments] = Path.split(path)
    {root, segments}
  end

  defp resolve_segments(root, resolved_segments, []), do: {:ok, join_path(root, resolved_segments)}

  defp resolve_segments(root, resolved_segments, [segment | rest]) do
    candidate_path = join_path(root, resolved_segments ++ [segment])

    case File.lstat(candidate_path) do
      {:ok, %File.Stat{type: :symlink}} ->
        with {:ok, target} <- :file.read_link_all(String.to_charlist(candidate_path)) do
          resolved_target = Path.expand(IO.chardata_to_string(target), join_path(root, resolved_segments))
          {target_root, target_segments} = split_absolute_path(resolved_target)
          resolve_segments(target_root, [], target_segments ++ rest)
        end

      {:ok, _stat} ->
        resolve_segments(root, resolved_segments ++ [segment], rest)

      {:error, :enoent} ->
        {:ok, join_path(root, resolved_segments ++ [segment | rest])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp join_path(root, segments) when is_list(segments) do
    Enum.reduce(segments, root, fn segment, acc -> Path.join(acc, segment) end)
  end

  defp descendant_path?(candidate, root) do
    candidate_segments = normalized_segments(candidate)
    root_segments = normalized_segments(root)

    length(candidate_segments) > length(root_segments) and
      Enum.take(candidate_segments, length(root_segments)) == root_segments
  end

  defp normalized_segments(path) do
    path
    |> Path.expand()
    |> String.replace("\\", "/")
    |> String.split("/", trim: true)
    |> maybe_downcase_windows_segments()
  end

  defp maybe_downcase_windows_segments(segments) do
    case :os.type() do
      {:win32, _} -> Enum.map(segments, &String.downcase/1)
      _ -> segments
    end
  end
end
