# Star Conquest Soundpack for Mushclient

## Installation

* Ensure that you save all the files under StarCon_Soundpack in the same directory. They are so packaged for your convenience.
* In Mush, `CTRL+SHIFT+P`, `ALT+A`, navigate to the location where you saved the files, and select the `.xml`.
* You should see a confirmation message in your main output window.

## Commands

### Displaying information

* sp list: List all available event groups.
* sp list <group>: List all events in the given group
* sp list <group> <index>: Display detailed info about a particular event

### Gagging

* sp gag all <on|off>: Gag all/no event messages
* sp gag <group> <index> <on|off>: Gag/ungag a particular event message
* sp sub <group> <index> <string>: Replace the event message with the given string. %1- ... %9-style wildcards are available, as for any normal trigger
* sp sub <group> <index> none: Remove the substitution of the given event message

### Plugin Configuration

* sp volume <value>: Set the plugin's master volume (0 - 100)

### Misc

* sp version: Display the plugin's version info
