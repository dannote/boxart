defmodule Boxart.Render.GanttTest do
  use ExUnit.Case, async: true

  alias Boxart.Render.Gantt, as: GanttRenderer
  alias GanttRenderer.{Gantt, Section, Task}

  describe "basic rendering" do
    test "single task" do
      d = %Gantt{
        sections: [
          %Section{
            title: "Work",
            tasks: [%Task{title: "Do stuff", start: ~D[2024-01-01], end: ~D[2024-01-10]}]
          }
        ]
      }

      out = GanttRenderer.render(d)
      assert String.contains?(out, "Work")
      assert String.contains?(out, "Do stuff")
      assert String.contains?(out, "█")
    end

    test "with title" do
      d = %Gantt{
        title: "Project Plan",
        sections: [
          %Section{
            title: "Phase 1",
            tasks: [%Task{title: "Task A", start: ~D[2024-01-01], end: ~D[2024-01-15]}]
          }
        ]
      }

      out = GanttRenderer.render(d)
      assert String.contains?(out, "Project Plan")
      assert String.contains?(out, "Phase 1")
    end

    test "multiple sections" do
      d = %Gantt{
        sections: [
          %Section{
            title: "Design",
            tasks: [%Task{title: "Wireframes", start: ~D[2024-01-01], end: ~D[2024-01-10]}]
          },
          %Section{
            title: "Build",
            tasks: [%Task{title: "Backend", start: ~D[2024-01-10], end: ~D[2024-02-01]}]
          }
        ]
      }

      out = GanttRenderer.render(d)
      assert String.contains?(out, "Design")
      assert String.contains?(out, "Build")
      assert String.contains?(out, "Wireframes")
      assert String.contains?(out, "Backend")
    end

    test "task styles" do
      d = %Gantt{
        sections: [
          %Section{
            title: "Tasks",
            tasks: [
              %Task{title: "Done", start: ~D[2024-01-01], end: ~D[2024-01-05], is_done: true},
              %Task{title: "Active", start: ~D[2024-01-05], end: ~D[2024-01-10], is_active: true},
              %Task{title: "Critical", start: ~D[2024-01-05], end: ~D[2024-01-08], is_crit: true},
              %Task{
                title: "Milestone",
                start: ~D[2024-01-10],
                end: ~D[2024-01-10],
                is_milestone: true
              }
            ]
          }
        ]
      }

      out = GanttRenderer.render(d)
      assert String.contains?(out, "░")
      assert String.contains?(out, "▓")
      assert String.contains?(out, "◆")
    end

    test "date axis" do
      d = %Gantt{
        sections: [
          %Section{
            title: "S",
            tasks: [%Task{title: "T", start: ~D[2024-01-01], end: ~D[2024-03-01]}]
          }
        ]
      }

      out = GanttRenderer.render(d)
      assert String.contains?(out, "Jan")
    end

    test "ASCII mode" do
      d = %Gantt{
        sections: [
          %Section{
            title: "S",
            tasks: [%Task{title: "T", start: ~D[2024-01-01], end: ~D[2024-01-10]}]
          }
        ]
      }

      out = GanttRenderer.render(d, charset: :ascii)
      assert String.contains?(out, "#")
      refute String.contains?(out, "█")
    end

    test "empty diagram returns empty string" do
      assert GanttRenderer.render(%Gantt{}) == ""
    end

    test "custom width" do
      d = %Gantt{
        sections: [
          %Section{
            title: "S",
            tasks: [%Task{title: "T", start: ~D[2024-01-01], end: ~D[2024-01-10]}]
          }
        ]
      }

      narrow = GanttRenderer.render(d, width: 40)
      wide = GanttRenderer.render(d, width: 120)
      narrow_w = narrow |> String.split("\n") |> Enum.map(&String.length/1) |> Enum.max()
      wide_w = wide |> String.split("\n") |> Enum.map(&String.length/1) |> Enum.max()
      assert wide_w > narrow_w
    end
  end
end
