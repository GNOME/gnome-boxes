Feature: General

  Background:
    * Make sure that gnome-boxes is running
    * Wait until overview is loaded

  @open_help_via_shortcut
  Scenario: Open help via shortcut
    * Hit "<F1>"
    Then Help is shown

  @open_help_via_menu
  Scenario: Open help from menu
    * Select "Help" from supermenu
    Then Help is shown

  @open_about_via_menu
  Scenario: Open about from menu
    * Select "About" from supermenu
    * Press "Credits"
    * Press "About"
    Then About is shown

  @quit_via_panel
  Scenario: Quit Boxes via super menu
    * Select "Quit" from supermenu
    Then Boxes are not running

  @quit_via_shortcut
  Scenario: Quit Boxes via shortcut
    * Select "Quit" from supermenu
    Then Boxes are not running

  @no_boxes
  Scenario: No boxes installed
    Then No box is visible

  @download_iso_http
  Scenario: Download iso http
    * Create new box from url "http://ftp.vim.org/os/Linux/distr/tinycorelinux/5.x/x86/archive/5.2/Core-5.2.iso"
    * Wait for "sleep 10" end
    * Hit "Enter"
    * Save IP for machine "Core-5"
    * Press "back" in vm
    Then Box "Core-5" "does" exist
    Then Ping "Core-5"

  @customize_machine_before_installation
  Scenario: Customize machine before installation
    * Create new box from menu "Core-5"
    * Customize mem to 64 MB
    * Press "Create"
    * Wait for "sleep 10" end
    Then "65536 KiB" is visible with command "DOM=$(virsh list |grep boxes |awk {'print $1'}); virsh dominfo $DOM"

  @rename_via_button
  Scenario: Rename via button
    * Initiate new box "Core-5" installation
    * Select "Core-5" box
    * Press "Properties"
    * Rename "Core-5" to "Kernel-6" via "button"
    * Press "Back"
    * Quit Boxes
    * Start Boxes
    Then Box "Kernel-6" "does" exist

  @rename_via_label
  Scenario: Rename via label
    * Initiate new box "Core-5" installation
    * Select "Core-5" box
    * Press "Properties"
    * Rename "Core-5" to "Kernel-6" via "label"
    * Press "Back"
    * Quit Boxes
    * Start Boxes
    Then Box "Kernel-6" "does" exist

  @start_box_from_console
  Scenario: Start box directly from console
    * Create new box "Core-5"
    Then Ping "Core-5"
    * Quit Boxes
    * Start box name "Core-5"
    * Type "sudo ifconfig eth0 down"
    * Wait for "sleep 4" end
    Then Cannot ping "Core-5"

  @search_via_shortcut
  Scenario: Search via shotcut
    * Initiate new box "Core-5" installation
    * Initiate new box "Core-5" installation
    * Hit "<Ctrl><f>"
    * Type "Core-5 2"
    Then Box "Core-5 2" "does" exist
    Then Box "Core-5" "does not" exist
    * Hit "<Ctrl><a>"
    * Type "Core"
    Then Box "Core-5 2" "does" exist
    Then Box "Core-5" "does" exist

  @search_via_button
  Scenario: Search via button
    * Initiate new box "Core-5" installation
    * Initiate new box "Core-5" installation
    * Press "Search"
    * Type "Core-5 2"
    Then Box "Core-5 2" "does" exist
    Then Box "Core-5" "does not" exist
    * Hit "<Ctrl><a>"
    * Type "Core"
    Then Box "Core-5 2" "does" exist
    Then Box "Core-5" "does" exist

  @search_escape
  Scenario: Return from search via Esc
    * Initiate new box "Core-5" installation
    * Initiate new box "Core-5" installation
    * Hit "<Ctrl><f>"
    * Type "Core-5 2"
    Then Box "Core-5 2" "does" exist
    Then Box "Core-5" "does not" exist
    * Hit "Esc"
    Then Box "Core-5 2" "does" exist
    Then Box "Core-5" "does" exist

### TBD ###
  # local_machine_paused_after_quit
  # import_from_system_broker
  # detach_from_system_broker
  # add_machine_from_system_broker_via_url
