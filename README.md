# Johnny's Raid Roll

A World of Warcraft 3.3.5a addon for the Warmane private server.

Flat-skinned replacement windows for the RaidRoll addon's roll UI, loot tracker, and settings panel.

## Requirements

**Requires the RaidRoll addon** (and optionally RaidRoll_LootTracker / RaidRoll_EPGP). This addon re-skins RaidRoll's windows. Open it from Johnny's Addon Hub or Johnny's Raid Comp's launcher.

## Install

1. Go to [Releases](https://github.com/JohnnyL1993/JohnnysRaidRoll/releases) and download **`JohnnysRaidRoll-vX.Y.zip`** from the latest release.
   Don't use GitHub's green **Code → Download ZIP** button or the "Source code" zips. Those unpack as `JohnnysRaidRoll-main` or `JohnnysRaidRoll-1.0`, and WoW won't load an addon whose folder name doesn't match.
2. Extract it into `World of Warcraft\Interface\AddOns\`. You should end up with `Interface\AddOns\JohnnysRaidRoll\JohnnysRaidRoll.toc`.
3. Restart WoW, or log out to the character screen, and make sure the addon is enabled.

## Updating

Download the latest release zip, delete the old `JohnnysRaidRoll` folder, and extract the new one in its place.

## Other Johnny's addons

- [Johnny's Raid Comp](https://github.com/JohnnyL1993/JohnnysRaidComp)
- [Johnny's Warmane Addon Hub](https://github.com/JohnnyL1993/JohnnysAddonHub)
- [Johnny's Blacklist](https://github.com/JohnnyL1993/JohnnysBlackList)
- [Johnny's Currency Tracker](https://github.com/JohnnyL1993/JohnnysCurrencyBar)
- [Johnny's Gear Advisor](https://github.com/JohnnyL1993/JohnnysGearAdvisor)
- [Johnny's Professions](https://github.com/JohnnyL1993/JohnnysProfessions)
- [Johnny's Messenger](https://github.com/JohnnyL1993/JohnnysMessenger)
- [Johnny's Raid Browser](https://github.com/JohnnyL1993/JohnnysRaidBrowser)

## Releasing (maintainer notes)

1. Bump `## Version:` in the `.toc`.
2. Commit, then `git tag vX.Y` and `git push && git push --tags`.
3. The **Release** GitHub Action builds the zip and attaches it to the release.
