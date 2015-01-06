Feature: Import Images

  Background:
    * Make sure that gnome-boxes is running
    * Wait until overview is loaded

  @import_local_qcow2_image
  Scenario: Import local qcow2 image
    * Import machine "Core-5" from image "Downloads/Core-5.3.qcow2"
    Then Box "Core-5" "does" exist
    Then Ping "Core-5"

  @import_local_vmdk_image
  Scenario: Import local vmdk image
    * Import machine "Core-5" from image "Downloads/Core-5.3.vmdk"
    Then Box "Core-5" "does" exist
    Then Ping "Core-5"

  @restart_persistence
  Scenario: Restart persistence
    * Import machine "Core-5" from image "Downloads/Core-5.3.qcow2"
    * Import machine "Core-5" from image "Downloads/Core-5.3.vmdk"
    * Quit Boxes
    * Start Boxes
    Then Box "Core-5" "does" exist
    Then Box "Core-5 2" "does" exist

