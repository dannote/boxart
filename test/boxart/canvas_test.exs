defmodule Boxart.CanvasTest do
  use ExUnit.Case, async: true

  alias Boxart.Canvas

  describe "new/2 and get/3" do
    test "empty canvas returns spaces" do
      c = Canvas.new(5, 3)
      assert Canvas.get(c, 0, 0) == " "
      assert Canvas.get(c, 4, 2) == " "
    end

    test "out of bounds returns space" do
      c = Canvas.new(2, 2)
      assert Canvas.get(c, 10, 10) == " "
    end
  end

  describe "put/5" do
    test "places a character" do
      c = Canvas.new(5, 5) |> Canvas.put(1, 2, "X")
      assert Canvas.get(c, 1, 2) == "X"
    end

    test "ignores space character" do
      c = Canvas.new(5, 5) |> Canvas.put(1, 1, "A") |> Canvas.put(1, 1, " ")
      assert Canvas.get(c, 1, 1) == "A"
    end

    test "ignores out of bounds" do
      c = Canvas.new(2, 2) |> Canvas.put(10, 10, "X")
      assert Canvas.get(c, 10, 10) == " "
    end
  end

  describe "junction merging" do
    test "horizontal + vertical = cross" do
      c =
        Canvas.new(5, 5)
        |> Canvas.put(2, 2, "─")
        |> Canvas.put(2, 2, "│")

      assert Canvas.get(c, 2, 2) == "┼"
    end

    test "horizontal + down-right = T-junction" do
      c =
        Canvas.new(5, 5)
        |> Canvas.put(2, 2, "─")
        |> Canvas.put(2, 2, "┌")

      assert Canvas.get(c, 2, 2) == "┬"
    end

    test "vertical + right = T-junction" do
      c =
        Canvas.new(5, 5)
        |> Canvas.put(2, 2, "│")
        |> Canvas.put(2, 2, "─")

      assert Canvas.get(c, 2, 2) == "┼"
    end

    test "rounded corners have same directions as sharp" do
      c =
        Canvas.new(5, 5)
        |> Canvas.put(2, 2, "╭")
        |> Canvas.put(2, 2, "│")

      # ╭ = RIGHT|DOWN, │ = UP|DOWN => UP|DOWN|RIGHT = ├
      assert Canvas.get(c, 2, 2) == "├"
    end
  end

  describe "protection" do
    test "protected cells block plain overwrites" do
      c =
        Canvas.new(5, 5)
        |> Canvas.put(1, 1, "─")
        |> Canvas.protect(1, 1)
        |> Canvas.put(1, 1, "X", merge: true)

      assert Canvas.get(c, 1, 1) == "─"
    end

    test "protected cells accept junction merges adding new directions" do
      c =
        Canvas.new(5, 5)
        |> Canvas.put(1, 1, "─")
        |> Canvas.protect(1, 1)
        |> Canvas.put(1, 1, "│")

      assert Canvas.get(c, 1, 1) == "┼"
    end

    test "protected cells reject merges with no new directions" do
      c =
        Canvas.new(5, 5)
        |> Canvas.put(1, 1, "─")
        |> Canvas.protect(1, 1)
        |> Canvas.put(1, 1, "─")

      assert Canvas.get(c, 1, 1) == "─"
    end

    test "protected? returns correct state" do
      c = Canvas.new(5, 5) |> Canvas.protect(1, 1)
      assert Canvas.protected?(c, 1, 1)
      refute Canvas.protected?(c, 0, 0)
    end
  end

  describe "put_text/5" do
    test "places string characters" do
      c = Canvas.new(10, 3) |> Canvas.put_text(1, 0, "Hello")
      assert Canvas.get(c, 1, 0) == "H"
      assert Canvas.get(c, 2, 0) == "e"
      assert Canvas.get(c, 5, 0) == "o"
    end
  end

  describe "draw_horizontal/6 and draw_vertical/6" do
    test "draws horizontal line" do
      c = Canvas.new(10, 3) |> Canvas.draw_horizontal(1, 2, 5, "─")
      assert Canvas.get(c, 2, 1) == "─"
      assert Canvas.get(c, 3, 1) == "─"
      assert Canvas.get(c, 5, 1) == "─"
      assert Canvas.get(c, 1, 1) == " "
    end

    test "draws vertical line" do
      c = Canvas.new(3, 10) |> Canvas.draw_vertical(1, 2, 5, "│")
      assert Canvas.get(c, 1, 2) == "│"
      assert Canvas.get(c, 1, 3) == "│"
      assert Canvas.get(c, 1, 5) == "│"
      assert Canvas.get(c, 1, 1) == " "
    end
  end

  describe "to_string/1" do
    test "renders simple canvas" do
      c =
        Canvas.new(5, 3)
        |> Canvas.put(0, 0, "┌")
        |> Canvas.put(1, 0, "─")
        |> Canvas.put(2, 0, "┐")
        |> Canvas.put(0, 1, "│")
        |> Canvas.put(2, 1, "│")
        |> Canvas.put(0, 2, "└")
        |> Canvas.put(1, 2, "─")
        |> Canvas.put(2, 2, "┘")

      expected = "┌─┐\n│ │\n└─┘"
      assert Canvas.to_string(c) == expected
    end

    test "trims trailing whitespace and empty lines" do
      c = Canvas.new(5, 5) |> Canvas.put(0, 0, "X")
      assert Canvas.to_string(c) == "X"
    end
  end

  describe "flip_vertical/1" do
    test "flips rows and remaps characters" do
      c =
        Canvas.new(3, 3)
        |> Canvas.put(0, 0, "┌")
        |> Canvas.put(2, 0, "┐")
        |> Canvas.put(0, 2, "└")
        |> Canvas.put(2, 2, "┘")
        |> Canvas.flip_vertical()

      assert Canvas.get(c, 0, 0) == "┌"
      assert Canvas.get(c, 2, 0) == "┐"
      assert Canvas.get(c, 0, 2) == "└"
      assert Canvas.get(c, 2, 2) == "┘"
    end
  end

  describe "flip_horizontal/1" do
    test "flips columns and remaps characters" do
      c =
        Canvas.new(3, 3)
        |> Canvas.put(0, 0, "┌")
        |> Canvas.put(2, 0, "┐")
        |> Canvas.put(0, 2, "└")
        |> Canvas.put(2, 2, "┘")
        |> Canvas.flip_horizontal()

      assert Canvas.get(c, 0, 0) == "┌"
      assert Canvas.get(c, 2, 0) == "┐"
      assert Canvas.get(c, 0, 2) == "└"
      assert Canvas.get(c, 2, 2) == "┘"
    end
  end

  describe "resize/3" do
    test "expands canvas" do
      c = Canvas.new(2, 2) |> Canvas.resize(5, 5)
      assert c.width == 5
      assert c.height == 5
    end

    test "does not shrink" do
      c = Canvas.new(5, 5) |> Canvas.resize(2, 2)
      assert c.width == 5
      assert c.height == 5
    end
  end

  describe "direction constants" do
    test "bitfield values" do
      assert Canvas.dir_up() == 1
      assert Canvas.dir_down() == 2
      assert Canvas.dir_left() == 4
      assert Canvas.dir_right() == 8
    end
  end

  describe "direction_to_char/0" do
    test "returns expected mappings" do
      import Bitwise
      map = Canvas.direction_to_char()
      assert Map.get(map, 4 ||| 8) == "─"
      assert Map.get(map, 1 ||| 2) == "│"
      assert Map.get(map, 4 ||| 8 ||| 1 ||| 2) == "┼"
    end
  end

  describe "String.Chars protocol" do
    test "works with string interpolation" do
      c = Canvas.new(3, 1) |> Canvas.put(0, 0, "A")
      assert "#{c}" == "A"
    end
  end
end
