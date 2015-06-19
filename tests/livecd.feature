Feature: LiceCD

  Background:
    * Make sure that gnome-boxes is running
    * Wait until overview is loaded

  @new_local_livecd_box_via_file
  Scenario: New local liveCD box via file
    * Create new box from file "Downloads/Core-5.3.iso"
    * Press "Create"
    * Wait for "sleep 3" end
    * Hit "Enter"
    * Wait for "sleep 5" end
    * Save IP for machine "Core-5"
    * Press "back" in "Core-5" vm
    Then Box "Core-5" "does" exist
    Then Ping "Core-5"

  @new_local_livecd_box_via_iso
  Scenario: New local liveCD box
    * Create new box from menu "Core-5"
    * Press "Create"
    * Wait for "sleep 3" end
    * Hit "Enter"
    * Wait for "sleep 5" end
    * Save IP for machine "Core-5"
    * Press "back" in "Core-5" vm
    Then Box "Core-5" "does" exist
    Then Ping "Core-5"

  @create_five_local_liveCD_boxes
  Scenario: Create five liveCD boxes
    * Create new box "Core-5"
    Then Ping "Core-5"
    * Create new box "Core-5 2" from "Core-5" menuitem
    Then Ping "Core-5 2"
    * Create new box "Core-5 3" from "Core-5" menuitem
    Then Ping "Core-5 3"
    * Create new box "Core-5 4" from "Core-5" menuitem
    Then Ping "Core-5 4"
    * Create new box "Core-5 5" from "Core-5" menuitem
    Then Ping "Core-5 5"

  @go_into_local_livecd_box
  Scenario: Go into local liveCD box
    * Create new box "Core-5"
    * Box "Core-5" "does" exist
    * Ping "Core-5"
    * Go into "Core-5" box
    * Wait for "sleep 2" end
    * Type text "sudo ifconfig eth0 down" and return
    * Wait for "sleep 5" end
    Then Cannot ping "Core-5"

  @delete_local_livecd_box
  Scenario: Delete local liveCD box
    * Create new box "Core-5"
    * Select "Core-5" box
    * Press "Delete"
    * Close warning
    * Wait for "sleep 2" end
    Then Box "Core-5" "does not" exist
    Then Cannot ping "Core-5"

  @delete_local_livecd_box_via_context_menu
  Scenario: Delete local liveCD box via context menu
    * Create new box "Core-5"
    * Launch "Delete" for "Core-5" box
    * Close warning
    * Wait for "sleep 2" end
    Then Box "Core-5" "does not" exist
    Then Cannot ping "Core-5"

  @undo_delete_local_livecd_box
  Scenario: Undo Delete of local liveCD box
    * Create new box "Core-5"
    When Box "Core-5" "does" exist
    When Ping "Core-5"
    * Select "Core-5" box
    * Press "Delete"
    * Press "Undo"
    Then Box "Core-5" "does" exist
    Then Ping "Core-5"

  @delete_five_local_livecd_boxes
  Scenario: Delete five local liveCD boxes
    * Create new box "Core-5"
    * Create new box "Core-5 2" from "Core-5" menuitem
    * Create new box "Core-5 3" from "Core-5" menuitem
    * Create new box "Core-5 4" from "Core-5" menuitem
    * Create new box "Core-5 5" from "Core-5" menuitem
    * Select "Core-5" box
    * Select "Core-5 2" box
    * Select "Core-5 3" box
    * Select "Core-5 4" box
    * Select "Core-5 5" box
    * Press "Delete"
    * Close warning
    * Wait for "sleep 2" end
    Then Box "Core-5" "does not" exist
    Then Cannot ping "Core-5"
    Then Box "Core-5 2" "does not" exist
    Then Cannot ping "Core-5 2"
    Then Box "Core-5 3" "does not" exist
    Then Cannot ping "Core-5 3"
    Then Box "Core-5 4" "does not" exist
    Then Cannot ping "Core-5 4"
    Then Box "Core-5 5" "does not" exist
    Then Cannot ping "Core-5 5"

  # https://bugzilla.gnome.org/show_bug.cgi?id=742392
  @poweroff_local_livecd_box
  Scenario: Power off local liveCD box
    * Create new box "Core-5"
    * Box "Core-5" "does" exist
    * Ping "Core-5"
    * Go into "Core-5" box
    * Wait for "sleep 1" end
    * Type text "sudo poweroff" and return
    * Wait for "sleep 20" end
    Then Box "Core-5" "does not" exist
    Then Cannot ping "Core-5"

  @pause_livecd_box
  Scenario: Pause liveCD box
    * Create new box "Core-5"
    When Ping "Core-5"
    * Select "Core-5" box
    * Press "Pause"
    * Wait for "sleep 8" end
    Then Cannot ping "Core-5"

  @resume_livecd_box
  Scenario: Resume liveCD box
    * Create new box "Core-5"
    * Select "Core-5" box
    * Press "Pause"
    * Wait for "sleep 2" end
    * Hit "Esc"
    * Go into "Core-5" box
    * Wait for "sleep 4" end
    Then Ping "Core-5"

  @force_shutdown_local_machine
  Scenario: Force off local liveCD box
    * Create new box "Core-5"
    * Launch "Properties" for "Core-5" box
    * Press "System"
    * Press "Force Shutdown"
    Then Box "Core-5" "does" exist
    Then Cannot ping "Core-5"

  @livecd_restart_persistence
  Scenario: LiveCD restart persistence
    * Initiate new box "Core-5" installation
    * Initiate new box "Core-5 2" installation from "Core-5" menuitem
    * Import machine "Core-5" from image "Downloads/Core-5.3.qcow2"
    * Import machine "Core-5" from image "Downloads/Core-5.3.vmdk"
    * Quit Boxes
    * Start Boxes
    Then Box "Core-5" "does" exist
    Then Box "Core-5 2" "does" exist
    Then Box "Core-5 3" "does" exist
    Then Box "Core-5 4" "does" exist
