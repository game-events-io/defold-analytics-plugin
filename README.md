# GameEventsIO Defold Extension

This is the Defold client for [GameEvents.io](https://game-events.io).

## Installation

### Remote (Recommended)
Add the library ZIP URL (`https://github.com/game-events-io/defold-analytics-plugin/archive/refs/heads/main.zip`) to `dependencies` in your `game.project` file.

### Local
If you have the source code locally (e.g. in a monorepo), simply copy the `game_events_io` folder into your Defold project's directory (e.g. alongside your `main` folder).

## Example Setup

If you are new to Defold, remember that scripts must be attached to a Game Object in the bootstrap collection to run:

1.  Create a script (e.g., `main.script`) and add the **Usage** code below.
2.  Create a Game Object (right-click in `main.collection` -> Add Game Object).
3.  Add a Component to that Game Object (right-click GO -> Add Component File) and select your `main.script`.
4.  Ensure `main.collection` is set as the **Main Collection** in `game.project` (under **Bootstrap**).

## Usage

1. Require the module:
```lua
local game_events = require "game_events_io.game_events_io"
```

2. Initialize with your API Key:
```lua
function init(self)
    game_events.init("YOUR_API_KEY")
end
```

3. Log events:
```lua
game_events.log_event("level_complete", { level = 5, score = 1000 })
```

4. Set user properties:
```lua
game_events.set_user_property("is_premium", true)
```

5. Enable debug logging (optional):
```lua
game_events.set_debug_mode(true)
```

## Features
- Automatic session management (`session_start` event, `session_id`, `user_id`).
- Automatic device info collection.
- Offline event batching and retry logic.
