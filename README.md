# dontmindthis

Run the loader:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/goon123456/dontmindthis/main/loader.luau"))()
```

The full script lives in [`loader.luau`](loader.luau), so the in-game code stays short.

Waypoints save between sessions when your environment supports `writefile`, `readfile`, and `isfile`. They are stored per Roblox place and user in a local JSON file named like `dontmindthis_waypoints_<placeId>_<userId>.json`.
The Waypoints tab can also render saved waypoints as small diamond markers with labels.

The Player tab includes rebindable noclip, vehicle fly, a safe manual player-hitbox extender, and a cleaner ESP panel with enable/keybind controls, max distance, chams, name/distance/health display toggles, and category toggles for players, zombies, vehicles, and corpses. Vehicle fly uses WASD with Space/E to rise and LeftCtrl/Q to descend while seated in a vehicle.
