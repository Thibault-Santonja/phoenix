defmodule Portfolio.Photography.EventHandlers.AlbumPublishedHandlerTest do
  use ExUnit.Case, async: false

  alias Portfolio.Photography.EventHandlers.AlbumPublishedHandler

  describe "AlbumPublishedHandler" do
    test "handler is started and registered" do
      # Verify handler is running
      assert Process.whereis(AlbumPublishedHandler) != nil
      assert Process.alive?(Process.whereis(AlbumPublishedHandler))
    end

    test "handler is supervised and restarts on crash" do
      pid = Process.whereis(AlbumPublishedHandler)
      assert pid != nil

      # Kill the handler
      Process.exit(pid, :kill)

      # Give supervisor time to restart
      Process.sleep(100)

      # Handler should be restarted with different PID
      new_pid = Process.whereis(AlbumPublishedHandler)
      assert new_pid != nil
      assert new_pid != pid
      assert Process.alive?(new_pid)
    end
  end
end
