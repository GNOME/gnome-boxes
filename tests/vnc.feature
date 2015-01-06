Feature: Vnc

  Background:
    * Make sure that gnome-boxes is running
    * Wait until overview is loaded

  @new_vnc_localhost_box
  Scenario: New VNC box
    * Create new box from url "vnc://localhost:5901;"
    * Press "Create"
    * Wait for "sleep 2" end
    Then Box "localhost" "does" exist
    * Go into "localhost" box
    * Wait for "sleep 10" end
    * Hit "<Super_L>"
    * Wait for "sleep 5" end
    * Type "gnome-terminal"
    * Wait for "sleep 10" end
    * Type "echo 'walderon' > /tmp/vnc_text.txt"
    Then "walderon" is visible with command "cat /tmp/vnc_text.txt"
    Then Press "back" in vm

  @vnc_restart_persistence
  Scenario: VNC restart persistence
    * Create new box from url "vnc://localhost:5901;"
    * Press "Create"
    * Quit Boxes
    * Start Boxes
    Then Box "localhost" "does" exist
