# PathWatcher

[![Wally](https://img.shields.io/badge/Wally-0.1.1-blue)](https://wally.run/package/breezy1214/pathwatcher?version=0.1.1)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

> **Reactive path observation for Fusion with efficient delta-based change detection.**

PathWatcher is a focused library for **observing specific paths in Fusion reactive states** with **minimal performance overhead**. It leverages DeltaTable for efficient, delta-based change detection — processing *only* what actually changed.

---

## Overview

### What It Does
- Integrates seamlessly with **Fusion reactive states**
- Detects changes efficiently using **DeltaTable**
- Supports **path-based observation** for nested table (`"Currency.Gold"`)

### What It’s Not
- Not a replacement for Fusion
- Not for plain tables — use [Replica](https://github.com/MadStudioRoblox/Replica)
- Not a networking solution

---

## Features

- **Fusion-Native** – Designed for reactive tables in Fusion
- **Delta Integration** – Processes only changed paths for high efficiency
- **Path-Based Observation** – Supports string or array paths (e.g. `{"Inventory", "Weapons", 1, "Durability"}`)
- **Dual APIs** – Use `.Value` reactively or `.onChange()` for side effects

---

## Quick Start

```luau
local Fusion = require("Fusion")
local PathWatcher = require("PathWatcher")

local scope = Fusion.scoped()
local playerData = scope:Value({
	Currency = { Gold = 100, Cash = 500 },
	Level = 5,
	Inventory = { Weapons = {}, Potions = {} }
})

-- Observe specific path
local goldObserver = PathWatcher.new(playerData, "Currency.Gold")

-- Reactive UI example
local goldLabel = scope:New("TextLabel")({
	Text = scope:Computed(function()
		return "Gold: " .. tostring(goldObserver.Value:get())
	end)
})

-- Side effect example
goldObserver:onChange(function(newValue, oldValue)
	print(`Gold changed: {oldValue} → {newValue}`)
end)

playerData:set({ Currency = { Gold = 200, Cash = 500 } })
-- Output: "Gold changed: 100 → 200"

goldObserver:Destroy()
```

---

## API Reference

### `PathWatcher.new(tableState, path, onUpdate?)`

Creates a path observer that tracks changes to a specific keypath in a Fusion state.

**Parameters:**
- `tableState` — Reactive Fusion state (Value)
- `path` — String (`"Currency.Gold"`) or table (`{"Currency", "Gold"}`)
- `onUpdate` — Optional callback `(path, oldValue, newValue)`

**Returns:** `PathWatcher`  
Contains:
- `.Value` — Fusion state of the observed value  
- `.get()` — Current value snapshot  
- `.onChange(fn)` — Listener for changes  
- `.Destroy()` — Cleanup method  

---

### `PathWatcher.newMultiple(tableState, paths)`

Creates multiple observers efficiently.

```luau
local observers = PathWatcher.newMultiple(playerData, {
	"Currency.Gold",
	"Currency.Cash",
	"Level"
})
```

**Returns:** `{ [string]: PathWatcher }`

---

### `PathWatcher.setDebug(enabled)`

Enable or disable internal debug logs.

```luau
PathWatcher.setDebug(true)
```

---

## Internal Mechanics

### Fusion Integration

1. Fusion state changes trigger a delta computation.
2. PathWatcher checks if its path is affected.
3. If yes, it updates its internal Fusion value.
4. `.onChange()` listeners fire with old/new values.
5. Any dependent Fusion UI updates automatically.

### Path Detection Rules

- **Exact Match** — Directly observed keypath changes  
- **Child Change** — Subpath beneath the observer changes  
- **Parent Change** — Parent keypath replaced or restructured

---

## Performance Benefits

- Updates only affected observers  
- No full-state traversal  
- Avoids redundant reactivity updates  
- Efficient cleanup and memory safety

---

## FAQ

**Q:** Can I use this with plain tables?  
**A:** No — use Replica.

**Q:** Does it replace Fusion?  
**A:** No, it extends it for path-level observation.

**Q:** Why not use Fusion observers directly?  
**A:** This adds delta efficiency, path filtering, and old/new comparisons.

**Q:** Multiple paths?  
**A:** Yes — use `newMultiple()`.

**Q:** Works on server?  
**A:** Yes, if Fusion runs server-side.

**Q:** Performance?  
**A:** Processes *only* modified paths, not entire states.
