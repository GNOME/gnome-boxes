Feature: Multi Window

  Background:
    * Make sure that gnome-boxes is running
    * Wait until overview is loaded

  @open_in_new_window
  Scenario: Open box in new window
    * Initiate new box "Core-5" installation
    * Select "Core-5" box
    * Press "Open in new window"
    * Wait for "sleep 2" end
    Then Boxes app has "2" windows
    Then Verify back button "is not" visible for machine "Core-5"

  @poweroff_in_new_window
  Scenario: Poweroff in new window
    * Create new box "Core-5"
    * Select "Core-5" box
    * Press "Open in new window"
    * Wait for "sleep 2" end
    * Type text "sudo poweroff" and return
    * Wait for "sleep 20" end
    Then Boxes app has "1" windows

  @open_three_new_windows
  Scenario: Open three new windows
    * Create new box "Core-5"
    * Create new box "Core-5 2" from "Core-5" menuitem
    * Create new box "Core-5 3" from "Core-5" menuitem
    * Select "Core-5" box
    * Select "Core-5 2" box
    * Select "Core-5 3" box
    * Open "Core-5, Core-5 2, Core-5 3" in new windows
    Then Boxes app has "4" windows
    Then Verify back button "is not" visible for machine "Core-5"
    Then Verify back button "is not" visible for machine "Core-5 2"
    Then Verify back button "is not" visible for machine "Core-5 3"
    When Ping "Core-5"
    When Ping "Core-5 2"
    When Ping "Core-5 3"
    * Focus "Core-5" window
    * Type text "sudo ifconfig eth0 down" and return
    * Focus "Core-5 2" window
    * Type text "sudo ifconfig eth0 down" and return
    * Focus "Core-5 3" window
    * Type text "sudo ifconfig eth0 down" and return
    Then Cannot ping "Core-5"
    Then Cannot ping "Core-5 2"
    Then Cannot ping "Core-5 3"
