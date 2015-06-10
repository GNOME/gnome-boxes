Feature: Spice

  Background:
    * Make sure that gnome-boxes is running
    * Wait until overview is loaded

  @new_spice_localhost_box
  Scenario: New spice box
    * Create new box "Core-5"
    * Create new box from url "spice://127.0.0.1?port=5900;"
    * Wait for "sleep 2" end
    * Press "Create"
    Then Box "127.0.0.1" "does" exist
    * Go into "127.0.0.1" box
    * Wait for "sleep 1" end
    * Type text "sudo ifconfig eth0 down" and return
    * Wait for "sleep 5" end
    Then Cannot ping "Core-5"

  @spice_restart_persistence
  Scenario: Spice system persistence
    * Initiate new box "Core-5" installation
    * Create new box from url "spice://127.0.0.1?port=5900;"
    * Wait for "sleep 1" end
    * Press "Create"
    * Quit Boxes
    * Start Boxes
    Then Box "127.0.0.1" "does" exist
