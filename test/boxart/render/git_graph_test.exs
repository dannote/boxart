defmodule Boxart.Render.GitGraphTest do
  use ExUnit.Case, async: true

  alias Boxart.Render.GitGraph, as: GGRenderer
  alias GGRenderer.{Branch, Commit, GitGraph}

  describe "basic rendering" do
    test "single commit" do
      d = %GitGraph{
        branches: [%Branch{name: "main"}],
        commits: [%Commit{id: "init", branch: "main"}]
      }

      out = GGRenderer.render(d)
      assert String.contains?(out, "main")
      assert String.contains?(out, "init")
      assert String.contains?(out, "●")
    end

    test "linear history" do
      d = %GitGraph{
        branches: [%Branch{name: "main"}],
        commits: [
          %Commit{id: "a1", branch: "main"},
          %Commit{id: "a2", branch: "main"},
          %Commit{id: "a3", branch: "main"}
        ]
      }

      out = GGRenderer.render(d)

      for id <- ~w(a1 a2 a3) do
        assert String.contains?(out, id)
      end

      assert String.contains?(out, "─")
    end

    test "branch and merge" do
      d = %GitGraph{
        branches: [%Branch{name: "main"}, %Branch{name: "feature"}],
        commits: [
          %Commit{id: "init", branch: "main"},
          %Commit{id: "feat", branch: "main"},
          %Commit{id: "wip", branch: "feature", parents: ["feat"]},
          %Commit{id: "done", branch: "feature"},
          %Commit{id: "merge", branch: "main", parents: ["feat", "done"]}
        ]
      }

      out = GGRenderer.render(d)
      assert String.contains?(out, "main")
      assert String.contains?(out, "feature")

      for id <- ~w(init feat wip done merge) do
        assert String.contains?(out, id)
      end
    end

    test "commit with tag" do
      d = %GitGraph{
        branches: [%Branch{name: "main"}],
        commits: [
          %Commit{id: "rel", branch: "main", tag: "v1.0"}
        ]
      }

      out = GGRenderer.render(d)
      assert String.contains?(out, "[v1.0]")
    end

    test "commit types" do
      d = %GitGraph{
        branches: [%Branch{name: "main"}],
        commits: [
          %Commit{id: "a", branch: "main", type: :normal},
          %Commit{id: "b", branch: "main", type: :reverse},
          %Commit{id: "c", branch: "main", type: :highlight}
        ]
      }

      out = GGRenderer.render(d)
      assert String.contains?(out, "●")
      assert String.contains?(out, "✖")
      assert String.contains?(out, "■")
    end

    test "ASCII mode" do
      d = %GitGraph{
        branches: [%Branch{name: "main"}],
        commits: [%Commit{id: "x", branch: "main", type: :normal}]
      }

      out = GGRenderer.render(d, charset: :ascii)
      assert String.contains?(out, "o")
      refute String.contains?(out, "●")
    end

    test "three branches" do
      d = %GitGraph{
        branches: [
          %Branch{name: "main"},
          %Branch{name: "dev"},
          %Branch{name: "hotfix"}
        ],
        commits: [
          %Commit{id: "c1", branch: "main"},
          %Commit{id: "c2", branch: "dev", parents: ["c1"]},
          %Commit{id: "c3", branch: "hotfix", parents: ["c1"]},
          %Commit{id: "c4", branch: "main", parents: ["c1", "c2"]}
        ]
      }

      out = GGRenderer.render(d)

      for name <- ~w(main dev hotfix) do
        assert String.contains?(out, name)
      end
    end

    test "empty diagram returns empty string" do
      assert GGRenderer.render(%GitGraph{}) == ""
    end
  end
end
