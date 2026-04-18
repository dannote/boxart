defmodule Boxart.RenderTest do
  use ExUnit.Case, async: true

  defp graph(direction, edges, node_overrides \\ %{}) do
    g =
      Enum.reduce(edges, Graph.new(), fn e, acc ->
        acc
        |> ensure_vertex(e.source, node_overrides)
        |> ensure_vertex(e.target, node_overrides)
        |> Graph.add_edge(e.source, e.target, label: e.label)
      end)

    {g, direction}
  end

  defp ensure_vertex(g, id, overrides) do
    if Graph.has_vertex?(g, id) do
      g
    else
      labels = Map.get(overrides, id, [])
      Graph.add_vertex(g, id, labels)
    end
  end

  defp simple_edges(pairs) do
    Enum.map(pairs, fn {s, t} -> %{source: s, target: t, label: nil} end)
  end

  defp labeled_edges(triples) do
    Enum.map(triples, fn {s, t, label} -> %{source: s, target: t, label: label} end)
  end

  defp render({g, direction}, opts \\ []) do
    Boxart.render(g, Keyword.put_new(opts, :direction, direction))
  end

  describe "basic rendering" do
    test "single chain LR" do
      output =
        graph(:lr, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> render()

      for node <- ["A", "B", "C"] do
        assert String.contains?(output, node), "Node #{node} missing"
      end

      assert String.contains?(output, "►") or String.contains?(output, ">")
    end

    test "single chain TD" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> render()

      for node <- ["A", "B", "C"] do
        assert String.contains?(output, node)
      end

      assert String.contains?(output, "▼") or String.contains?(output, "v")
    end

    test "branching TD" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"A", "C"}]))
        |> render()

      for node <- ["A", "B", "C"] do
        assert String.contains?(output, node)
      end
    end

    test "diamond pattern" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"A", "C"}, {"B", "D"}, {"C", "D"}]))
        |> render()

      for node <- ["A", "B", "C", "D"] do
        assert String.contains?(output, node)
      end
    end
  end

  describe "multiline labels" do
    test "newline in label renders both lines" do
      output =
        graph(
          :td,
          simple_edges([{"A", "B"}]),
          %{
            "A" => [label: "Line 1\nLine 2"],
            "B" => [label: "Target"]
          }
        )
        |> render()

      assert String.contains?(output, "Line 1")
      assert String.contains?(output, "Line 2")
      assert String.contains?(output, "Target")
    end
  end

  describe "edge labels" do
    test "labeled edges show labels" do
      output =
        graph(:lr, labeled_edges([{"A", "B", "yes"}, {"A", "C", "no"}]))
        |> render()

      assert String.contains?(output, "yes")
      assert String.contains?(output, "no")
    end
  end

  describe "ASCII mode" do
    test "produces no unicode box-drawing characters" do
      output =
        graph(:lr, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> render(charset: :ascii)

      box_chars = ~c[┌┐└┘─│├┤┬┴┼╭╮╰╯►◄▲▼┄┆━┃╋]

      used =
        output
        |> String.graphemes()
        |> Enum.filter(fn ch ->
          <<cp::utf8>> = ch
          cp in box_chars
        end)

      assert used == [], "ASCII mode contains unicode chars: #{inspect(used)}"
    end

    test "renders all nodes" do
      output =
        graph(:lr, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> render(charset: :ascii)

      for node <- ["A", "B", "C"] do
        assert String.contains?(output, node)
      end
    end
  end

  describe "rendering quality" do
    test "valid unicode output" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> render()

      refute String.contains?(output, "\uFFFD")
      assert output == output |> String.to_charlist() |> List.to_string()
    end

    test "reasonable dimensions" do
      output =
        graph(:lr, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> render()

      lines = String.split(output, "\n")
      assert length(lines) <= 200
      max_width = lines |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
      assert max_width <= 500
    end

    test "all nodes appear in output" do
      edges = simple_edges([{"A", "B"}, {"A", "C"}, {"B", "D"}, {"C", "D"}, {"D", "E"}])
      output = graph(:td, edges) |> render()

      for node <- ["A", "B", "C", "D", "E"] do
        assert String.contains?(output, node), "Node #{node} missing from output"
      end
    end
  end

  describe "gap parameter" do
    test "smaller gap produces narrower LR output" do
      edges = simple_edges([{"A", "B"}, {"B", "C"}, {"C", "D"}, {"D", "E"}])

      w4 =
        graph(:lr, edges)
        |> render(gap: 4)
        |> String.split("\n")
        |> Enum.map(&String.length/1)
        |> Enum.max()

      w1 =
        graph(:lr, edges)
        |> render(gap: 1)
        |> String.split("\n")
        |> Enum.map(&String.length/1)
        |> Enum.max()

      assert w1 < w4
    end

    test "gap=0 is clamped to gap=1" do
      edges = simple_edges([{"A", "B"}, {"B", "C"}])
      g = graph(:lr, edges)
      assert render(g, gap: 0) == render(g, gap: 1)
    end

    test "all nodes visible with compact gap" do
      edges = simple_edges([{"A", "B"}, {"B", "C"}, {"C", "D"}, {"D", "E"}, {"E", "F"}])
      output = graph(:lr, edges) |> render(gap: 1)

      for node <- ~w(A B C D E F) do
        assert String.contains?(output, node)
      end
    end
  end

  describe "node shapes" do
    test "diamond shape renders diamond corners" do
      output =
        graph(
          :td,
          simple_edges([{"A", "B"}]),
          %{"A" => [label: "Q?", shape: :diamond]}
        )
        |> render()

      assert String.contains?(output, "◇") or String.contains?(output, "/")
    end

    test "rounded shape renders rounded corners" do
      output =
        graph(
          :td,
          simple_edges([{"A", "B"}]),
          %{"A" => [label: "Hi", shape: :rounded]}
        )
        |> render()

      assert String.contains?(output, "╭") or String.contains?(output, "+")
    end
  end

  describe "regression: RL direction (bug #15)" do
    test "RL renders text left-to-right, not reversed" do
      output =
        graph(:lr, simple_edges([{"A", "B"}]), %{"A" => [label: "Left"], "B" => [label: "Right"]})
        |> render(direction: :rl)

      assert String.contains?(output, "Left")
      assert String.contains?(output, "Right")
      refute String.contains?(output, "tfeL")
      refute String.contains?(output, "thgiR")
    end

    test "RL node order is reversed — Right appears before Left" do
      output =
        graph(:lr, simple_edges([{"A", "B"}]), %{"A" => [label: "Alpha"], "B" => [label: "Beta"]})
        |> render(direction: :rl)

      right_pos = :binary.match(output, "Beta")
      left_pos = :binary.match(output, "Alpha")
      assert right_pos != nil
      assert left_pos != nil

      assert elem(right_pos, 0) < elem(left_pos, 0),
             "In RL mode, Beta (originally right) should appear first"
    end

    test "RL renders all nodes" do
      output =
        graph(:lr, simple_edges([{"A", "B"}, {"B", "C"}]))
        |> render(direction: :rl)

      for node <- ["A", "B", "C"] do
        assert String.contains?(output, node)
      end
    end
  end

  describe "regression: BT direction (bug #15)" do
    test "BT renders text correctly, not upside-down" do
      output =
        graph(:td, simple_edges([{"A", "B"}]), %{"A" => [label: "Top"], "B" => [label: "Bottom"]})
        |> render(direction: :bt)

      assert String.contains?(output, "Top")
      assert String.contains?(output, "Bottom")
    end

    test "BT places Bottom above Top" do
      output =
        graph(:td, simple_edges([{"A", "B"}]), %{"A" => [label: "Top"], "B" => [label: "Bottom"]})
        |> render(direction: :bt)

      bottom_pos = :binary.match(output, "Bottom")
      top_pos = :binary.match(output, "Top")
      assert bottom_pos != nil
      assert top_pos != nil

      assert elem(bottom_pos, 0) < elem(top_pos, 0),
             "In BT mode, Bottom (originally lower) should appear first"
    end
  end

  describe "structural: all directions (ported from termaid)" do
    test "LR: A and B on same row" do
      output = graph(:lr, simple_edges([{"A", "B"}])) |> render()
      lines = String.split(output, "\n")

      a_rows =
        Enum.with_index(lines)
        |> Enum.filter(fn {l, _} -> String.contains?(l, "A") end)
        |> Enum.map(&elem(&1, 1))

      b_rows =
        Enum.with_index(lines)
        |> Enum.filter(fn {l, _} -> String.contains?(l, "B") end)
        |> Enum.map(&elem(&1, 1))

      assert a_rows != [] and b_rows != []
      assert hd(a_rows) == hd(b_rows), "In LR, A and B should be on the same row"
    end

    test "TD: A above B" do
      output = graph(:td, simple_edges([{"A", "B"}])) |> render()
      lines = String.split(output, "\n")

      a_row =
        Enum.find_value(Enum.with_index(lines), fn {l, i} ->
          if String.contains?(l, "A"), do: i
        end)

      b_row =
        Enum.find_value(Enum.with_index(lines), fn {l, i} ->
          if String.contains?(l, "B"), do: i
        end)

      assert a_row != nil and b_row != nil
      assert a_row < b_row, "In TD, A should appear above B"
    end

    test "BT: A below B (reversed)" do
      output = graph(:td, simple_edges([{"A", "B"}])) |> render(direction: :bt)
      lines = String.split(output, "\n")

      a_row =
        Enum.find_value(Enum.with_index(lines), fn {l, i} ->
          if String.contains?(l, "A"), do: i
        end)

      b_row =
        Enum.find_value(Enum.with_index(lines), fn {l, i} ->
          if String.contains?(l, "B"), do: i
        end)

      assert a_row != nil and b_row != nil
      assert a_row > b_row, "In BT, A should appear below B (flow goes up)"
    end

    test "RL: A to the right of B" do
      output = graph(:lr, simple_edges([{"A", "B"}])) |> render(direction: :rl)
      lines = String.split(output, "\n")

      a_line = Enum.find(lines, &String.contains?(&1, "A"))
      b_line = Enum.find(lines, &String.contains?(&1, "B"))

      assert a_line != nil and b_line != nil
      a_col = :binary.match(output, "A") |> elem(0)
      b_col = :binary.match(output, "B") |> elem(0)
      assert a_col > b_col, "In RL, A should be to the right of B"
    end

    test "self-loop renders more than one line" do
      output = graph(:lr, simple_edges([{"A", "A"}])) |> render()
      lines = String.split(output, "\n")
      assert length(lines) > 1, "Self-loop should produce more than one line"
      assert String.contains?(output, "A")
    end

    test "cycle renders with reasonable dimensions" do
      output = graph(:lr, simple_edges([{"A", "B"}, {"B", "C"}, {"C", "A"}])) |> render()

      for node <- ["A", "B", "C"] do
        assert String.contains?(output, node), "Node #{node} missing from cycle"
      end

      lines = String.split(output, "\n")
      assert length(lines) < 50, "3-node cycle should be under 50 lines"
    end

    test "edge labels are visible" do
      output =
        graph(:td, labeled_edges([{"A", "B", "yes"}, {"A", "C", "no"}]))
        |> render()

      assert String.contains?(output, "yes")
      assert String.contains?(output, "no")
    end

    test "disconnected components both render" do
      edges = simple_edges([{"A", "B"}, {"C", "D"}])
      output = graph(:td, edges) |> render()

      for node <- ["A", "B", "C", "D"] do
        assert String.contains?(output, node), "Node #{node} missing"
      end
    end
  end

  describe "rendering quality (ported from termaid)" do
    test "back edge has no trailing dangling characters" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"B", "C"}, {"C", "D"}, {"D", "A"}, {"D", "B"}]))
        |> render()

      for line <- String.split(output, "\n") do
        stripped = String.trim_trailing(line)

        refute String.ends_with?(stripped, "┼─"),
               "Trailing '─' after junction: #{inspect(stripped)}"

        refute String.ends_with?(stripped, "┴─"),
               "Trailing '─' after junction: #{inspect(stripped)}"
      end
    end

    test "single back edge has no trailing chars" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"B", "C"}, {"C", "A"}]))
        |> render()

      for line <- String.split(output, "\n") do
        stripped = String.trim_trailing(line)

        refute String.ends_with?(stripped, "┼─"),
               "Trailing '─' after junction: #{inspect(stripped)}"

        refute String.ends_with?(stripped, "┴─"),
               "Trailing '─' after junction: #{inspect(stripped)}"
      end
    end

    test "gap reduces width in LR" do
      edges = simple_edges([{"A", "B"}, {"B", "C"}, {"C", "D"}, {"D", "E"}])

      w4 =
        graph(:lr, edges)
        |> render(gap: 4)
        |> String.split("\n")
        |> Enum.map(&String.length/1)
        |> Enum.max()

      w1 =
        graph(:lr, edges)
        |> render(gap: 1)
        |> String.split("\n")
        |> Enum.map(&String.length/1)
        |> Enum.max()

      assert w1 < w4
    end

    test "gap reduces height in TD" do
      edges = simple_edges([{"A", "B"}, {"B", "C"}])
      h4 = graph(:td, edges) |> render(gap: 4) |> String.split("\n") |> length()
      h2 = graph(:td, edges) |> render(gap: 2) |> String.split("\n") |> length()
      assert h2 < h4
    end
  end

  describe "visual correctness (ported from termaid)" do
    test "label text stays within box borders" do
      output =
        graph(:td, simple_edges([{"A", "B"}]), %{"A" => [label: "Alpha"], "B" => [label: "Beta"]})
        |> render()

      lines = String.split(output, "\n")

      for line <- lines do
        trimmed = String.trim_trailing(line)

        # Skip non-content lines
        content_chars = String.replace(trimmed, ~r/[┌┐└┘─│├┤┬┴┼╭╮╰╯▲▼►◄─│ \s]/, "")

        if content_chars != "" do
          # Find the box borders
          has_borders = String.contains?(trimmed, "│") or String.contains?(trimmed, "|")

          if has_borders do
            # Check content is between the border characters
            left_border =
              case :binary.match(trimmed, "│") do
                {pos, _} ->
                  pos

                :nomatch ->
                  case :binary.match(trimmed, "|") do
                    {pos, _} -> pos
                    :nomatch -> nil
                  end
              end

            if left_border != nil do
              content_before = String.slice(trimmed, 0, left_border)

              content_before_clean =
                String.replace(content_before, ~r/[\s┌┐└┘─│├┤┬┴┼╭╮╰╯▲▼►◄\-+]/, "")

              assert content_before_clean == "",
                     "Label text '#{content_before_clean}' appears before left border: #{inspect(trimmed)}"
            end
          end
        end
      end
    end

    test "output height is reasonable for cycles" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"B", "C"}, {"C", "D"}, {"D", "A"}]))
        |> render()

      lines = String.split(output, "\n")

      assert length(lines) < 50,
             "4-node cycle should produce fewer than 50 lines, got #{length(lines)}"
    end

    test "no reversed text in any direction" do
      for dir <- [:td, :lr, :bt, :rl] do
        output =
          graph(:td, simple_edges([{"A", "B"}]), %{
            "A" => [label: "Hello"],
            "B" => [label: "World"]
          })
          |> render(direction: dir)

        refute String.contains?(output, "olleH"),
               "Reversed text found in #{dir} output"

        refute String.contains?(output, "dlroW"),
               "Reversed text found in #{dir} output"
      end
    end

    test "no excessive blank lines" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"B", "C"}, {"C", "D"}]))
        |> render()

      consecutive_empty =
        output
        |> String.split("\n")
        |> Enum.chunk_every(4, 1, :discard)
        |> Enum.any?(fn chunk -> Enum.all?(chunk, &(&1 == "")) end)

      refute consecutive_empty, "Output has more than 3 consecutive empty lines"
    end

    test "BT direction has no leading blank lines" do
      output =
        graph(:td, simple_edges([{"A", "B"}]))
        |> render(direction: :bt)

      refute String.starts_with?(output, "\n"), "BT output has leading blank lines"
    end

    test "ASCII diamond uses / and \\ not *" do
      output =
        graph(:td, simple_edges([{"A", "B"}]), %{"A" => [label: "Q?", shape: :diamond]})
        |> render(charset: :ascii)

      refute String.contains?(output, "*"), "ASCII diamond should not use * as diamond marker"

      assert String.contains?(output, "/") or String.contains?(output, "\\"),
             "ASCII diamond should use / or \\ as diamond marker"
    end

    test "fan-out with 4 children renders all nodes and arrows" do
      edges = simple_edges([{"A", "B"}, {"A", "C"}, {"A", "D"}, {"A", "E"}])
      output = graph(:td, edges) |> render()

      for node <- ~w(A B C D E) do
        assert String.contains?(output, node)
      end

      arrow_count = output |> String.graphemes() |> Enum.count(&(&1 == "▼"))
      assert arrow_count >= 4, "Expected at least 4 down arrows, got #{arrow_count}"
    end
  end

  describe "regression: wide labels (bug #11)" do
    test "long label text stays within box borders" do
      long_label = "This is a very long node label that should wrap"

      output =
        graph(:td, simple_edges([{"A", "B"}]), %{
          "A" => [label: long_label],
          "B" => [label: "Short"]
        })
        |> render()

      # The full unwrapped label should NOT appear on a single line
      refute String.contains?(output, long_label),
             "Long label should be wrapped, not rendered on a single line overflowing borders"

      # The label words should all appear (wrapped across lines)
      for word <- String.split(long_label) do
        assert String.contains?(output, word), "Word '#{word}' missing from output"
      end
    end

    test "wrapped text is centered within box borders" do
      output =
        graph(:td, simple_edges([{"A", "B"}]), %{
          "A" => [label: "Alpha Beta Gamma Delta"],
          "B" => [label: "End"]
        })
        |> render()

      lines = String.split(output, "\n")

      border_lines =
        Enum.filter(lines, fn line ->
          String.contains?(line, "│") or String.contains?(line, "|")
        end)

      for line <- border_lines do
        trimmed = String.trim_trailing(line)

        if String.match?(trimmed, ~r/[A-Za-z]/) do
          last_char = String.at(trimmed, -1)

          assert last_char in ["│", "|", ""],
                 "Text overflows border: #{inspect(trimmed)}"
        end
      end
    end
  end

  describe "regression: cycles gap expansion (bug #7)" do
    test "4-node cycle output height is reasonable" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"B", "C"}, {"C", "D"}, {"D", "A"}]))
        |> render()

      lines = String.split(output, "\n")
      assert length(lines) < 50, "4-node cycle should not produce #{length(lines)} lines"
    end

    test "cycle renders all nodes" do
      output =
        graph(:td, simple_edges([{"A", "B"}, {"B", "C"}, {"C", "A"}]))
        |> render()

      for node <- ["A", "B", "C"] do
        assert String.contains?(output, node), "Node #{node} missing from cycle output"
      end
    end

    test "back edge does not inflate gap expansion" do
      edges = simple_edges([{"A", "B"}, {"B", "C"}, {"C", "D"}, {"D", "A"}])
      output_cycle = graph(:td, edges) |> render()
      output_chain = graph(:td, Enum.take(edges, 3)) |> render()

      cycle_lines = String.split(output_cycle, "\n") |> length()
      chain_lines = String.split(output_chain, "\n") |> length()

      # The cycle should add at most ~50% overhead for the back edge routing
      assert cycle_lines <= chain_lines * 2,
             "Cycle (#{cycle_lines} lines) shouldn't be more than 2x chain (#{chain_lines} lines)"
    end
  end
end
