---
sidebar_position: 1
---

# About

PathWatcher is a focused library for **observing specific paths in Fusion reactive states** with **minimal performance overhead**. It leverages DeltaTable for efficient, delta-based change detection — processing *only* what actually changed.

### What It Does
- Integrates seamlessly with **Fusion reactive states**
- Detects changes efficiently using **DeltaTable**
- Supports **path-based observation** for nested table (`"Currency.Gold"`)

### What It’s Not
- Not a replacement for Fusion
- Not for plain tables — use [Replica](https://github.com/MadStudioRoblox/Replica)
- Not a networking solution

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

## FAQ

**Q:** Can I use this with plain tables?  
**A:** No — use [Replica](https://github.com/MadStudioRoblox/Replica).

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
