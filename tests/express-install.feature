Feature: Express install

  Background:
    * Make sure that gnome-boxes is running
    * Wait until overview is loaded

  @express_install_fedora_20
  Scenario: Express install Fedora 20
    * Create new box from url "http://mirrors.nic.cz/pub/fedora/linux/releases/20/Fedora/x86_64/iso/Fedora-20-x86_64-DVD.iso"
    * Hit "Tab"
    * Hit "Tab"
    * Type "test"
    * Press "Add Password"
    * Type "secretpasswordnumber1"
    * Press "Continue"
    * Press "Create"
    Then Installation of "Fedora 20" is finished in "30" minutes
    * Save IP for machine "Fedora 20"
    Then Box "Fedora 20" "does" exist
    Then Go into "Fedora 20" box
    Then Press "back" in "Fedora 20" vm
    Then Ping "Fedora 20"
    Then Verify "test" user with "secretpasswordnumber1" password in "Fedora 20"
