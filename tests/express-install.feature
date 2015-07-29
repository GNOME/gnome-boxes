Feature: Express install

  Background:
    * Make sure that gnome-boxes is running
    * Wait until overview is loaded

  @express_install_fedora_20
  Scenario: Express install Fedora 20
    * Create new box from url "http://mirrors.nic.cz/pub/fedora-archive/fedora/linux/releases/20/Fedora/x86_64/iso/Fedora-20-x86_64-DVD.iso"
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

  @express_install_fedora_21
  Scenario: Express install Fedora 21
    * Create new box from url "http://mirrors.nic.cz/pub/fedora/linux/releases/21/Server/x86_64/iso/Fedora-Server-netinst-x86_64-21.iso"
    * Hit "Tab"
    * Hit "Tab"
    * Type "test"
    * Press "Add Password"
    * Type "secretpasswordnumber1"
    * Press "Continue"
    * Press "Create"
    Then Installation of "Fedora 21" is finished in "30" minutes
    * Wait for "sleep 60" end
    Then Box "Fedora 21" "does" exist
    Then Go into "Fedora 21" box
    * Save IP for machine "Fedora 21"
    Then Press "back" in "Fedora 21" vm
    Then Ping "Fedora 21"
    Then Verify "test" user with "secretpasswordnumber1" password in "Fedora 21"
