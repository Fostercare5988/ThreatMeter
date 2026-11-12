# ThreatMeter

*Who's the boss's favourite? Now you'll know.*

A threat meter for World of Warcraft 1.12.1 groups. It shows who has the boss's
attention, how close you are to taking it, and warns you before you do.

## What you get

- **Pull aggro line on top.** How much more threat you need to take the boss off the
  tank: 10% more in melee range, 30% more outside it. When you are the tank it says
  "You hold aggro".
- **Bars, highest threat first.** One per player, in class colours, with threat per
  second, threat and percent. Your own bar is always red. Show 3 to 14 players; a
  narrow window drops columns so names always fit.
- **A little badge.** Your threat percent as a small number you can drag anywhere.
- **A gentle warning.** A red screen glow and a sound when you pass the level you
  choose. It repeats every 5 seconds and stays quiet while you hold aggro.
- **Light on your game.** The next question goes out as soon as the answer is back.
  Nothing runs between answers, and the bars ease by themselves.

Threat shows for bosses, elites, rare elites and rares you fight in a group. Turn on
"Normal enemies too" to see the rest.

## Install

1. On this page, click the green **Code** button, then **Download ZIP**.
2. Unzip it into `Interface\AddOns`. The folder must be called exactly `ThreatMeter`,
   so rename `ThreatMeter-main` if that is what you got, and end up with
   `Interface\AddOns\ThreatMeter`.
3. Start the game, make sure ThreatMeter is ticked, and go hit something.

## Needs

- [ClassicAPI](https://github.com/brues-code/ClassicAPI), loaded.
- A server that answers threat questions from groups (OctoWoW does). On any other
  server the title says "no threat data from the server".

If you used TWThreat, switch it off. Both ask the server the same question.

## Using it

- `/tm` opens the settings (also under Game Menu > AddOn Options > ThreatMeter).
- `/tm on` and `/tm off` turn ThreatMeter on and off. Off really is off: no window, no
  warnings and nothing asked of the server. The X on the window does the same.
- **Preview** in the settings shows sample players, so you can place the window and
  badge and try the warning without a fight.
- Drag the window by its title, or the badge by itself. **Lock position** stops that.

Made by Fostercare5988.
