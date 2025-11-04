--!strict
--[=[
	@class PathWatcher
	
	Reactive path observation for Fusion with efficient delta-based change detection.
	
	**Example usage:**
	```lua
	local Fusion = require("Fusion")
	local PathWatcher = require("PathWatcher")
	
	-- Your reactive data state
	local dataState = Fusion.scoped(Fusion):Value({ 
		Currency = { Gold = 100, Cash = 500 },
		Level = 1 
	})
	
	-- Observe a specific path
	local goldObserver = PathWatcher.new(dataState, "Currency.Gold")
	
	-- Method 1: Use the reactive Value in Fusion UI
	local scope = Fusion.scoped()
	local label = scope:New("TextLabel")({
		Text = scope:Computed(function()
			return "Gold: " .. tostring(goldObserver.Value:get())
		end)
	})
	
	-- Method 2: Use onChange listener for side effects
	local connection = goldObserver:onChange(function(newValue, oldValue)
		print(`Gold changed from {oldValue} to {newValue}`)
		-- Play sound, show notification, etc.
	end)
	
	-- Update your data (observers automatically detect changes)
	dataState:set({ Currency = { Gold = 200, Cash = 500 }, Level = 1 })
	
	-- Clean up when done
	connection:Disconnect()
	goldObserver:Destroy()
	```
]=]

-- Packages
local Fusion = require(script.Packages.Fusion)
local Signal = require(script.Packages.Signal)
local TableUtil = require(script.Packages.TableUtil)

-- Shared
local DeltaTable = require(script.Packages["Delta-Table"])

-- Types
type ValueObject<T> = Fusion.Value<{ any }>

--[=[
	@interface PathWatcher
	@within PathWatcher
	.Value Fusion.Value<any> -- The reactive Fusion state containing the path's value
	.get () -> any -- Get the current value snapshot
	.onChange (listener: (newValue: any, oldValue: any) -> ()) -> Connection -- Listen to changes with old/new values
	.Destroy () -> () -- Clean up the observer and internal resources
]=]
export type PathWatcher = {
	Value: ValueObject<{ any }>,
	get: () -> { any },
	onChange: (listener: (newValue: any, oldValue: any) -> ()) -> any,
	Destroy: (self: PathWatcher) -> (),
	_scope: any, -- Internal scope for cleanup
	_changeSignal: any, -- Internal signal for change notifications
	_pathArray: { string }, -- Store path for debugging
}

local PathWatcher = {}

local DEBUG = false

local function debugPrint(message: string)
	if not DEBUG then
		return
	end
	print("[PathWatcher] " .. message)
end

local function debugWarn(message: string)
	if not DEBUG then
		return
	end
	warn("[PathWatcher] " .. message)
end

local function getLengthOfTable(t): number
	local count = 0
	for _, _ in t do
		count += 1
	end
	return count
end

-- Helper function to extract value at a specific path
local function getValueAtPath(data: any, keys: { string }): any
	if not data then
		return nil
	end

	local value = data
	for _, key in ipairs(keys) do
		if typeof(value) ~= "table" or value[key] == nil then
			return nil
		end
		value = value[key]
	end

	-- Deep copy table values to prevent mutation
	if typeof(value) == "table" then
		value = TableUtil.Copy(value, true)
	end

	return value
end

-- Helper function to check if one path is a prefix of another
local function isPathPrefix(prefix: { string }, fullPath: { string }): boolean
	if #prefix > #fullPath then
		return false
	end

	for i = 1, #prefix do
		if prefix[i] ~= fullPath[i] then
			return false
		end
	end

	return true
end

-- Helper function to perform deep comparison of values
local function isDeepEqual(a: any, b: any): boolean
	-- If both values are nil or equal primitives, they're equal
	if a == b then
		return true
	end

	-- If one is nil but not the other, they're not equal
	if a == nil or b == nil then
		return false
	end

	-- If types don't match, they're not equal
	if typeof(a) ~= typeof(b) then
		return false
	end

	-- If they're not tables, they're already compared with ==
	if typeof(a) ~= "table" then
		return false
	end

	if getLengthOfTable(a) ~= getLengthOfTable(b) then
		return false
	end

	-- Check if all keys in a exist in b with the same values
	for k, v in pairs(a) do
		if not isDeepEqual(v, b[k]) then
			return false
		end
	end

	return true
end

--[=[
	Creates a new path observer that monitors changes to a specific path in a Fusion reactive state.
	Uses DeltaTable for efficient change detection (only processes changed paths).
	
	@param tableState Fusion.Value<{any}> -- Fusion reactive state containing the full table
	@param path string | {string} -- Path to observe (e.g., "Currency.Gold" or {"Currency", "Gold"})
	@param onUpdate ((path: {string}, oldValue: any, newValue: any) -> ())? -- Optional callback when path changes
	@return PathWatcher
	
	**Example:**
	```lua
	local observer = PathWatcher.new(playerDataState, "Currency.Gold")
	
	-- Use the reactive Value in UI
	scope:Computed(function()
		return observer.Value:get()
	end)
	
	-- Or use onChange for side effects
	observer:onChange(function(newValue, oldValue)
		print("Gold changed!")
	end)
	```
]=]
function PathWatcher.new(
	tableState: ValueObject<{ any }>,
	path: string | { string },
	onUpdate: ((path: { string }, oldValue: any, newValue: any) -> ())?
): PathWatcher
	local pathArray: { string } = if typeof(path) == "string" then string.split(path, ".") else path
	local pathString = if typeof(path) == "string" then path else table.concat(pathArray, ".")

	-- Create internal scope for this observer
	local observerScope = Fusion.scoped(Fusion)
	local state = observerScope:Value(nil)
	local previousTable: any = nil
	local changeSignal = Signal.new() -- Signal for onChange listeners

	debugPrint(`Creating observer for path: {pathString}`)

	-- Initialize with current value
	local currentTable = Fusion.peek(tableState)
	if currentTable then
		local initialValue = getValueAtPath(currentTable, pathArray)
		state:set(initialValue)
		previousTable = TableUtil.Copy(currentTable, true)
		debugPrint(`Initialized path {pathString} with value: {tostring(initialValue)}`)
	end

	-- Watch for changes using DeltaTable
	observerScope:Observer(tableState):onChange(function()
		local newTable = Fusion.peek(tableState)
		if not newTable then
			return
		end

		-- Create delta to detect changes
		local delta, changeCount = DeltaTable.Create(previousTable, newTable)

		if changeCount == 0 then
			debugPrint(`No changes detected for path {pathString}`)
			return
		end

		debugPrint(`Detected {changeCount} changes, checking path {pathString}`)

		-- Track if our specific path was affected
		local pathWasAffected = false
		local oldPathValue = getValueAtPath(previousTable, pathArray)
		local newPathValue: any = nil

		-- Apply delta with trace to detect if our path was changed
		DeltaTable.Apply(TableUtil.Copy(previousTable, true), delta, function(changePath: { string }, value: any)
			local changePathString = table.concat(changePath, ".")
			debugPrint(`Change detected at: {changePathString}`)

			-- CASE 1: Direct path match
			if #changePath == #pathArray then
				local matches = true
				for i = 1, #pathArray do
					if changePath[i] ~= pathArray[i] then
						matches = false
						break
					end
				end

				if matches then
					pathWasAffected = true
					newPathValue = value
					debugPrint(`Direct match for path {pathString}`)
					return
				end
			end

			-- CASE 2: Changed path is a child of our path
			if #changePath > #pathArray and isPathPrefix(pathArray, changePath) then
				pathWasAffected = true
				debugPrint(`Child path changed: {changePathString} affects {pathString}`)
				return
			end

			-- CASE 3: Changed path is a parent of our path
			if #changePath < #pathArray and isPathPrefix(changePath, pathArray) then
				pathWasAffected = true
				debugPrint(`Parent path changed: {changePathString} affects {pathString}`)
				return
			end
		end)

		if pathWasAffected then
			-- Get the actual new value from the new table
			if newPathValue == nil then
				newPathValue = getValueAtPath(newTable, pathArray)
			end

			-- Only update if value actually changed
			if not isDeepEqual(oldPathValue, newPathValue) then
				debugWarn(`Updating path {pathString} from {tostring(oldPathValue)} to {tostring(newPathValue)}`)
				state:set(newPathValue)

				-- Fire change signal with old and new values
				changeSignal:Fire(newPathValue, oldPathValue)

				if onUpdate then
					task.defer(onUpdate, pathArray, oldPathValue, newPathValue)
				end
			end
		end

		-- Update previous table reference
		previousTable = TableUtil.Copy(newTable, true)
	end)

	-- Create the observer object
	local observer: PathWatcher = {
		Value = state,
		get = function()
			return Fusion.peek(state)
		end,
		onChange = function(listener: (newValue: any, oldValue: any) -> ())
			return changeSignal:Connect(listener)
		end,
		_scope = observerScope,
		_changeSignal = changeSignal,
		_pathArray = pathArray,
		Destroy = function(self: PathWatcher)
			debugPrint(`Destroying observer for path {pathString}`)
			if self._changeSignal then
				self._changeSignal:DisconnectAll()
				self._changeSignal = nil
			end
			if self._scope then
				self._scope:doCleanup()
				self._scope = nil
			end
		end,
	}

	return observer
end

--[=[
	Creates multiple path observers at once for the same table state.
	Useful when you need to observe several paths efficiently.
	
	@param tableState Fusion.Value<{any}> -- Fusion reactive state containing the full table
	@param paths {string | {string}} -- Array of paths to observe
	@return {[string]: PathWatcher} -- Dictionary mapping path strings to observers
	
	**Example:**
	```lua
	local observers = PathWatcher.newMultiple(playerDataState, {
		"Currency.Gold",
		"Currency.Cash",
		"Level",
		"Kills"
	})
	
	observers["Currency.Gold"]:onChange(function(newValue)
		print("Gold:", newValue)
	end)
	
	-- Clean up all
	for _, observer in observers do
		observer:Destroy()
	end
	```
]=]
function PathWatcher.newMultiple(
	tableState: ValueObject<{ any }>,
	paths: { string | { string } }
): { [string]: PathWatcher }
	local observers: { [string]: PathWatcher } = {}

	for _, path in ipairs(paths) do
		local pathString = if typeof(path) == "string" then path else table.concat(path :: { string }, ".")
		observers[pathString] = PathWatcher.new(tableState, path)
	end

	return observers
end

--[=[
	Enables or disables debug logging for the PathWatcher module.
	
	@param enabled boolean
]=]
function PathWatcher.setDebug(enabled: boolean)
	DEBUG = enabled
end

return PathWatcher
