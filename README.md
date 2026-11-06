# zomboid-bandits-largemaps

[Project Zomboid (Build 42) mod](https://steamcommunity.com/sharedfiles/filedetails/?id=3834583588) that makes the wanderer groups of [Bandits](https://steamcommunity.com/workshop/filedetails/?id=3268487204) work on big maps like [Real USA](https://steamcommunity.com/sharedfiles/filedetails/?id=3829712469).

## Why

Bandits creates wanderer groups at places hardcoded to the Kentucky map (`BanditServer.Wanderers.destinations`: March Ridge, Muldraugh, …). The groups travel between them out of sight and only turn into NPCs within 70 tiles of a player. On Real USA those places are far away from every player, so:

- wanderer clans (`W_*`, Hermits, Legion, ArmyDesert, Baseball) are never met
- living groups are only removed once met, so they fill up the limit of 100 groups for good

YANMC Bandits Core keeps the same destinations, and logs these groups as `too_far` in its `[YANMC Ambient] session counters`.

## What it does

Server side, every game minute while a player is online:

- replaces the destinations with points 400 to 900 tiles around each online player, where groups start and roam
- moves every group that was not sent to a player away when it gets within 250 tiles of one, dead groups too, so their bodies don't show up either
- sends one group to each area every 1.8 to 3 days a player is online, about 0.4 groups per player per day. Players within 300 tiles of each other share an area and its groups, so playing together doesn't bring more of them
- the sent group walks up to its player and waits about 64 tiles away until Bandits (or YANMC) turns it into NPCs. Other groups are kept away from it, so it doesn't fight them on the way
- moves living, automatically spawned groups farther than 3000 tiles from every player to a far point

A player's wait only runs while they are online and is saved with the world. Groups placed by hand are left alone. All of these values are sandbox options on the "Bandits Wanderers for Large Maps" page.

The assault, defender, camper and roadblock spawns of Bandits already work on any map, as they are placed around the player.

On Real USA it also replaces the Kentucky town outlines YANMC uses to tell towns from countryside with the 828 town boxes of Real USA's town maps (`RealUSA.TOWN_MAPS`). YANMC's urban/rural sandbox options (`BanditSpawnsUrban`, `PoliceSpawnsRural`, …), its Week One events and its rural battle audio then follow the Real USA towns.

## Server config

Add the mod after Bandits and YANMC Bandits Core, and its workshop item to `WorkshopItems`:

```ini
Mods=...;Bandits2;...;YANMCBanditsCore;...;com.github.teruncius.banditslargemaps
WorkshopItems=...;3834583588
```

On other big maps YANMC still uses the Kentucky town outlines, so nearly everything counts as rural there. Set `PoliceSpawnsRural = true` in the `YANMCBanditsCoreFresh` sandbox options, otherwise police and SWAT never spawn.

## Development

```sh
just check  # syntax check the lua, needs luac
just link   # link workshop/ into ~/Zomboid/Workshop to test and upload it in game
just unlink # remove that symlink again
```

Upload from the main menu under Workshop. The game writes the item id into `workshop/workshop.txt`, commit it afterwards.
