-- Input lifecycle and event model.
--
-- This game runs on the Compy input API (doc/input_api.md). It
-- registers compy.input.hooks.* rather than love.* handlers --
-- the framework would capture love.* and run them as hooks
-- anyway, so the explicit form just says what is happening --
-- and its reserved chords and the whole Alt class are
-- compy.input.shortcuts entries, which run ahead of the hooks.
--
-- Key repeat is filtered by the isrepeat flag the API delivers
-- as the third hook argument. Text input is enabled to match
-- the IDE default (restoring it on exit is a no-op). The game
-- does NOT disable global key-repeat: it now COULD restore it,
-- since compy.before_exit fires on every stop path including
-- Ctrl+Esc, but the repeats are filtered rather than suppressed
-- and turning them off would change what the scenes see.
--
-- Ordering: the IDE delivers textinput BEFORE the matching
-- keypress (the reverse of desktop LOVE). So a "fresh keypress
-- arms a gate, its textinput consumes it" scheme cannot work --
-- the glyph arrives before anything arms it, and after a chord
-- (which clears such a gate) the next target is dropped. So
-- textinput is judged directly, with no gate. An Alt+key chord
-- is swallowed by the alt+* shortcut AND its glyph dropped
-- in appTextinput (a chord glyph CAN surface and is never a
-- target), so a chord cannot fumble a target. A held key emits
-- textinput, and textinput has no isrepeat flag of its own, so
-- the glyph is judged by whether its producing key is HELD --
-- which is what compy.input.keys_pressed answers. The release
-- boundary still leaks: a final key-repeat glyph can arrive
-- just after its keyup, so a key stays "stale" for a frame
-- after release (INPUT.upRecent, ours -- the framework drops a
-- key from the held set at the gateway, before dispatch).
--
-- Held modifier state is read live from
-- compy.input.keys_pressed through the INPUT proxy below. It
-- used to be a mirror this file maintained on every press and
-- release; the API exposes the set outside an event now
-- (Decision 20), which is what the key-cap renderer needs --
-- it reads INPUT.shift from draw, where there is no event
-- argument to consult.

-- Reads pass through to the framework's held set. `held` is
-- that set; `shift`/`ctrl`/`alt` fold the l/r pair, which the
-- raw set deliberately does not. Only `upRecent` is ours.
INPUT = setmetatable({ upRecent = { } }, {
  __index = function(_, k)
    if k == "held" then return compy.input.keys_pressed end
    if k == "shift" then return modHeld("lshift", "rshift") end
    if k == "ctrl" then return modHeld("lctrl", "rctrl") end
    if k == "alt" then return modHeld("lalt", "ralt") end
  end,
})

-- A key stays "stale" this many frames after its release, to
-- swallow a final key-repeat glyph arriving just after keyup.
INPUT_UP_GRACE = 1

-- The app's reserved keys, none of which reaches the scene.
--
-- stop_here is what says a combo is taken, so the action itself
-- does not have to know what happens after it returns.
-- ignore_repeat goes inside it wherever there IS an action,
-- because stop_here alone re-runs the action on every OS
-- repeat: a held ctrl+alt+up would ramp the notch every frame.
--
-- "alt+*" is the whole Alt class: every Alt chord is swallowed,
-- never reaching the scene as a typed target. It is stop_here()
-- with nothing to run, so there is no repeat to ignore.
-- alt+p is an exact binding and exact wins over the class.
-- Ctrl+Alt+H is NOT in the class -- a different modifier set is
-- a different class -- which is the "and not Ctrl" test this
-- file used to write out by hand before combo classes existed.
local function register_reserved()
  local fn = compy.input.fn
  local sc = compy.input.shortcuts.keypressed
  sc["shift+escape"] = fn.stop_here(fn.ignore_repeat(goBack))
  sc["ctrl+alt+up"] = fn.stop_here(fn.ignore_repeat(function()
    notchAdjust(1)
  end))
  sc["ctrl+alt+down"] = fn.stop_here(fn.ignore_repeat(function()
    notchAdjust(-1)
  end))
  sc["alt+*"] = fn.stop_here()
  sc["alt+p"] = fn.stop_here(fn.ignore_repeat(pauseToggle))
end

function inputInit()
  love.keyboard.setTextInput(true)
  INPUT.upRecent = { }
  compy.input.hooks.keypressed = appKeypressed
  compy.input.hooks.keyreleased = appKeyreleased
  compy.input.hooks.textinput = appTextinput
  register_reserved()
end

function modHeld(a, b)
  local held = compy.input.keys_pressed
  if held[a] or held[b] then
    return true
  end
  return false
end

function isMod(k)
  return k == "lshift" or k == "rshift"
    or k == "lctrl" or k == "rctrl"
    or k == "lalt" or k == "ralt"
end

function goBack()
  if isGameScene(ACTIVE) then
    gotoScene("menu")
  end
end

function notchAdjust(delta)
  local s = SCENES[ACTIVE]
  if s and s.onNotch then s.onNotch(delta) end
end

-- Whether a TEXTINPUT glyph should be dropped: its producing
-- key is still held (a repeat -- textinput has no isrepeat flag
-- of its own), or was released within INPUT_UP_GRACE frames,
-- which catches a final glyph trailing just after keyup.
-- Keypresses do not use this: they have the real flag.
function inputStale(k)
  if INPUT.held[k] then return true end
  local up = INPUT.upRecent[k]
  if not up then return false end
  return DBG_FRAME - up <= INPUT_UP_GRACE
end

-- isr is the API's isrepeat (third hook argument): a held key
-- is filtered at the source instead of inferred from the held
-- set. capslock is exempt (its release may not arrive, wedging
-- the set and freezing Caps). Scene input is also dropped while
-- the help overlay is up (the game is frozen behind it).
function appKeypressed(k, _, isr)
  if isr and k ~= "capslock" then return end
  dbgLog("KP " .. k)
  if k == "capslock" then capsToggle() end
  if PAUSED then return end
  if helpOverlayShown() then return end
  local s = SCENES[ACTIVE]
  if s and s.keypressed then s.keypressed(k) end
end

function appKeyreleased(k)
  dbgLog("KR " .. k)
  INPUT.upRecent[k] = DBG_FRAME
  local s = SCENES[ACTIVE]
  if s and s.keyreleased then s.keyreleased(k) end
end

-- textinput is judged by the scene (the per-glyph stale filter
-- lives there); dropped here while paused or behind help. A
-- glyph made with Alt or Ctrl held is a chord, never a target
-- (only Shift modifies a target), so drop it too.
function appTextinput(t)
  if PAUSED then return end
  if INPUT.alt then return end
  if INPUT.ctrl then return end
  if helpOverlayShown() then return end
  dbgLog("TI " .. t .. " sh=" .. tostring(INPUT.shift))
  if isAlphaChar(t) then
    capsReconcile(t, INPUT.shift)
  end
  local s = SCENES[ACTIVE]
  if s and s.textinput then s.textinput(t) end
end
