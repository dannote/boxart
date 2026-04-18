defmodule Boxart.Render.SequenceTest do
  use ExUnit.Case, async: true

  alias Boxart.Render.Sequence

  alias Sequence.{
    Activate,
    Block,
    BlockSection,
    Destroy,
    Message,
    Note,
    Participant,
    SequenceDiagram
  }

  defp diagram(participants, events, opts \\ []) do
    %SequenceDiagram{
      participants: participants,
      events: events,
      autonumber: Keyword.get(opts, :autonumber, false)
    }
  end

  defp p(id, label \\ nil, type \\ :participant) do
    %Participant{id: id, label: label || id, type: type}
  end

  defp msg(from, to, text, opts \\ []) do
    %Message{
      from: from,
      to: to,
      text: text,
      line_type: Keyword.get(opts, :line_type, :solid),
      arrow_type: Keyword.get(opts, :arrow_type, :arrow)
    }
  end

  describe "basic rendering" do
    test "two participants with a message" do
      d = diagram([p("A", "Alice"), p("B", "Bob")], [msg("A", "B", "Hello")])
      output = Sequence.render(d)

      assert String.contains?(output, "Alice")
      assert String.contains?(output, "Bob")
      assert String.contains?(output, "Hello")
      assert String.contains?(output, "►") or String.contains?(output, ">")
    end

    test "empty diagram" do
      d = diagram([], [])
      output = Sequence.render(d)
      assert is_binary(output)
    end

    test "single participant no messages" do
      d = diagram([p("A")], [])
      output = Sequence.render(d)
      assert String.contains?(output, "A")
    end

    test "three participants chain" do
      d =
        diagram(
          [p("A"), p("B"), p("C")],
          [msg("A", "B", "req"), msg("B", "C", "fwd")]
        )

      output = Sequence.render(d)

      for name <- ["A", "B", "C"], do: assert(String.contains?(output, name))
      assert String.contains?(output, "req")
      assert String.contains?(output, "fwd")
    end
  end

  describe "message types" do
    test "dashed message" do
      d = diagram([p("A"), p("B")], [msg("A", "B", "reply", line_type: :dotted)])
      output = Sequence.render(d)
      assert String.contains?(output, "reply")
      assert String.contains?(output, "┄") or String.contains?(output, ".")
    end

    test "self-message" do
      d = diagram([p("A")], [msg("A", "A", "think")])
      output = Sequence.render(d)
      assert String.contains?(output, "think")
      assert String.contains?(output, "┐") or String.contains?(output, "+")
    end

    test "open arrow" do
      d = diagram([p("A"), p("B")], [msg("A", "B", "open", arrow_type: :open)])
      output = Sequence.render(d)
      assert String.contains?(output, "open")
      refute String.contains?(output, "►")
    end

    test "right-to-left message" do
      d = diagram([p("A"), p("B")], [msg("B", "A", "back")])
      output = Sequence.render(d)
      assert String.contains?(output, "back")
      assert String.contains?(output, "◄") or String.contains?(output, "<")
    end
  end

  describe "actors" do
    test "actor participant draws stick figure" do
      d = diagram([p("A", "Alice", :actor), p("B", "Bob")], [msg("A", "B", "Hi")])
      output = Sequence.render(d)
      assert String.contains?(output, "O")
      assert String.contains?(output, "Alice")
    end
  end

  describe "autonumber" do
    test "messages get numbered" do
      d =
        diagram(
          [p("A"), p("B")],
          [msg("A", "B", "first"), msg("B", "A", "second")],
          autonumber: true
        )

      output = Sequence.render(d)
      assert String.contains?(output, "1: first")
      assert String.contains?(output, "2: second")
    end
  end

  describe "notes" do
    test "note right of participant" do
      d =
        diagram(
          [p("A"), p("B")],
          [%Note{text: "Important", position: :right_of, participants: ["A"]}]
        )

      output = Sequence.render(d)
      assert String.contains?(output, "Important")
    end

    test "note over participant" do
      d =
        diagram(
          [p("A"), p("B")],
          [%Note{text: "Shared", position: :over, participants: ["A"]}]
        )

      output = Sequence.render(d)
      assert String.contains?(output, "Shared")
    end
  end

  describe "blocks" do
    test "loop block renders borders and label" do
      d =
        diagram(
          [p("A"), p("B")],
          [%Block{kind: "loop", label: "retry", events: [msg("A", "B", "ping")]}]
        )

      output = Sequence.render(d)
      assert String.contains?(output, "[loop]")
      assert String.contains?(output, "retry")
      assert String.contains?(output, "ping")
    end

    test "alt block with else section" do
      d =
        diagram(
          [p("A"), p("B")],
          [
            %Block{
              kind: "alt",
              label: "success",
              events: [msg("A", "B", "ok")],
              sections: [%BlockSection{label: "failure", events: [msg("A", "B", "err")]}]
            }
          ]
        )

      output = Sequence.render(d)
      assert String.contains?(output, "[alt]")
      assert String.contains?(output, "[failure]")
      assert String.contains?(output, "ok")
      assert String.contains?(output, "err")
    end
  end

  describe "activation and destroy" do
    test "activation changes lifeline character" do
      d =
        diagram(
          [p("A"), p("B")],
          [
            %Activate{participant: "B", active: true},
            msg("A", "B", "call"),
            %Activate{participant: "B", active: false}
          ]
        )

      output = Sequence.render(d)
      assert String.contains?(output, "║") or String.contains?(output, "[")
    end

    test "destroy marks lifeline" do
      d =
        diagram(
          [p("A"), p("B")],
          [msg("A", "B", "kill"), %Destroy{participant: "B"}]
        )

      output = Sequence.render(d)
      assert String.contains?(output, "╳") or String.contains?(output, "X")
    end
  end

  describe "ascii mode" do
    test "no unicode box-drawing characters" do
      d = diagram([p("A"), p("B")], [msg("A", "B", "hi")])
      output = Sequence.render(d, charset: :ascii)

      unicode_chars = ~c[┌┐└┘─│├┤┬┴┼╭╮╰╯►◄▲▼┄┆━┃╋║╳]

      used =
        output
        |> String.graphemes()
        |> Enum.filter(fn ch ->
          <<cp::utf8>> = ch
          cp in unicode_chars
        end)

      assert used == [], "ASCII mode contains unicode chars: #{inspect(used)}"
    end
  end

  describe "output quality" do
    test "valid unicode output" do
      d =
        diagram(
          [p("A"), p("B"), p("C")],
          [msg("A", "B", "x"), msg("B", "C", "y"), msg("C", "A", "z")]
        )

      output = Sequence.render(d)
      refute String.contains?(output, "\uFFFD")
    end

    test "lifelines are present" do
      d = diagram([p("A"), p("B")], [msg("A", "B", "test")])
      output = Sequence.render(d)
      assert String.contains?(output, "┆") or String.contains?(output, ":")
    end

    test "reasonable dimensions" do
      d =
        diagram(
          [p("A"), p("B"), p("C"), p("D")],
          [msg("A", "B", "a"), msg("B", "C", "b"), msg("C", "D", "c")]
        )

      output = Sequence.render(d)
      lines = String.split(output, "\n")
      assert length(lines) <= 100
      max_width = lines |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
      assert max_width <= 500
    end
  end
end
