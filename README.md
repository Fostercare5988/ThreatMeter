# ThreatMeter

Everyone's threat on your target in a group fight, how much more you need to pull
aggro, and a warning before you do, for OctoWoW (WoW 1.12.1).

## What it does

- **Threat from the server.** In a party or raid, while you fight a boss, an elite, a
  rare elite or a rare, ThreatMeter asks the server who holds how much threat on your
  target: one question at a time, up to ten a second. If the server stays silent for
  three seconds, the title says so.
- **One bar per player**, most threat first, in class colours, your own in red; each
  with threat per second, threat and percent of the tank's threat. You are always on
  the list. A narrow window leaves out threat per second, then threat.
- **Pull aggro +N** on top: the threat you still need to take aggro (110% of the
  tank's in melee, 130% at range), or "You hold aggro".
- **A badge** with your percent, to drag anywhere.
- **The warning** past 80% of the tank's threat: a red pulse at the screen's edge, a
  sound and a taskbar flash, at most every 5 seconds, never while you hold aggro.
- **Preview** shows sample players out of combat, to place the window and the badge.

Drag the window by its title; right-click the title for the settings. `/tm off`
(or the X) turns ThreatMeter off: no questions to the server, no window. `/tm on`
turns it on again.

## DLLs it calls

ClassicAPI: the Settings window, `PLAYER_IN_COMBAT_CHANGED`, `GROUP_ROSTER_UPDATE`,
`RegisterUnitEvent` (a target's combat flag), `C_Timer`, `C_ClassColor`,
`AbbreviateNumbers`, eased status bars, animation groups and `FlashClientIcon`. No DLL
can read threat on a mob, so the numbers come from the server's own addon messages.

## Install

Unzip the release into `Interface\AddOns` so that
`Interface\AddOns\ThreatMeter\ThreatMeter.toc` exists, and restart the game.
`/tm` opens the settings (also under AddOn Options).
