# dontmindthis

Run the loader:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/goon123456/dontmindthis/main/loader.luau"))()
```

The full script lives in [`loader.luau`](loader.luau), so the in-game code stays short.

Waypoints save between sessions when your environment supports `writefile`, `readfile`, and `isfile`. They are stored per Roblox place and user in a local JSON file named like `dontmindthis_waypoints_<placeId>_<userId>.json`.

The Player tab includes a rebindable noclip toggle and a basic ESP toggle with player distance and a health bar.
