defmodule Boxart.Render.PieChartTest do
  use ExUnit.Case, async: true

  alias Boxart.Render.PieChart
  alias PieChart.PieChart, as: Chart

  defp chart(slices, opts \\ []) do
    %Chart{
      title: Keyword.get(opts, :title, ""),
      slices: slices,
      show_data: Keyword.get(opts, :show_data, false)
    }
  end

  describe "basic rendering" do
    test "empty chart" do
      output = PieChart.render(chart([]))
      assert is_binary(output)
    end

    test "single slice" do
      output = PieChart.render(chart([{"Dogs", 100}]))
      assert String.contains?(output, "Dogs")
      assert String.contains?(output, "100.0%")
    end

    test "two slices" do
      output = PieChart.render(chart([{"Cats", 60}, {"Dogs", 40}]))
      assert String.contains?(output, "Cats")
      assert String.contains?(output, "Dogs")
      assert String.contains?(output, "█") or String.contains?(output, "░")
    end

    test "multiple slices with percentages" do
      slices = [{"A", 50}, {"B", 30}, {"C", 20}]
      output = PieChart.render(chart(slices))

      assert String.contains?(output, "50.0%")
      assert String.contains?(output, "30.0%")
      assert String.contains?(output, "20.0%")
    end
  end

  describe "title" do
    test "renders title when provided" do
      output = PieChart.render(chart([{"A", 100}], title: "My Chart"))
      assert String.contains?(output, "My Chart")
    end

    test "no extra space without title" do
      with_title = PieChart.render(chart([{"A", 100}], title: "Title"))
      without_title = PieChart.render(chart([{"A", 100}]))

      with_lines = String.split(with_title, "\n") |> length()
      without_lines = String.split(without_title, "\n") |> length()
      assert with_lines > without_lines
    end
  end

  describe "show data" do
    test "includes raw values" do
      output = PieChart.render(chart([{"A", 42}, {"B", 58}], show_data: true))
      assert String.contains?(output, "42")
      assert String.contains?(output, "58")
    end
  end

  describe "bar characters" do
    test "uses fill characters" do
      output = PieChart.render(chart([{"A", 50}, {"B", 50}]))
      assert String.contains?(output, "█") or String.contains?(output, "░")
    end

    test "uses bar separator" do
      output = PieChart.render(chart([{"A", 100}]))
      assert String.contains?(output, "┃") or String.contains?(output, "|")
    end
  end

  describe "ascii mode" do
    test "no unicode fill characters" do
      slices = [{"A", 40}, {"B", 35}, {"C", 25}]
      output = PieChart.render(chart(slices), charset: :ascii)

      refute String.contains?(output, "█")
      refute String.contains?(output, "░")
      refute String.contains?(output, "┃")
    end

    test "uses ascii fill characters" do
      output = PieChart.render(chart([{"X", 100}]), charset: :ascii)
      assert String.contains?(output, "#")
    end
  end

  describe "output quality" do
    test "valid unicode" do
      output = PieChart.render(chart([{"A", 50}, {"B", 50}]))
      refute String.contains?(output, "\uFFFD")
    end

    test "reasonable dimensions" do
      slices = Enum.map(1..8, fn i -> {"Item #{i}", i * 10} end)
      output = PieChart.render(chart(slices))
      lines = String.split(output, "\n")
      assert length(lines) <= 50
      max_w = lines |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
      assert max_w <= 200
    end

    test "labels are right-aligned" do
      slices = [{"Short", 50}, {"Much Longer Label", 50}]
      output = PieChart.render(chart(slices))
      assert String.contains?(output, "Short")
      assert String.contains?(output, "Much Longer Label")
    end
  end
end
