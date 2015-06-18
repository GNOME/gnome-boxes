Feature: Snapshots

  Background:
    * Make sure that gnome-boxes is running
    * Wait until overview is loaded

  @snapshots_create_an_revert
  Scenario: Create snapshots and revert to them
    * Create new box "Core-5"
    * Create snapshot "working network" from machine "Core-5"
    * Go into "Core-5" box
    * Wait for "sleep 1" end
    * Type text "sudo ifconfig eth0 down" and return
    * Press "back" in "Core-5" vm
    * Create snapshot "network down" from machine "Core-5"
    When "network down" is visible with command "virsh snapshot-current boxes-unknown |grep description"
    When Cannot ping "Core-5"
    * Revert machine "Core-5" to state "working network"
    When "working network" is visible with command "virsh snapshot-current boxes-unknown |grep description"
    When Ping "Core-5"
    * Revert machine "Core-5" to state "network down"
    Then Cannot ping "Core-5"

  @delete_snapshots
  Scenario: Delete snapshots
    * Initiate new box "Core-5" installation
    * Create snapshot "working network" from machine "Core-5"
    * Create snapshot "network down" from machine "Core-5"
    * Delete machines "Core-5" snapshot "working network"
    * Delete machines "Core-5" snapshot "network down"
    Then "error: domain 'boxes-unknown' has no current snapshot" is visible with command "virsh snapshot-current boxes-unknown"
