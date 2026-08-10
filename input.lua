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
-- Ordering: keypressed and textinput have NO fixed order
-- between them (doc/development/internals/user_input.md, "Data
-- flow"). The IDE delivers the glyph first; desktop LOVE
-- delivers the keypress first. Nothing here may depend on
-- which, and two schemes are ruled out by that:
-- "a fresh keypress arms a gate, its textinput consumes it"
-- fails wherever the glyph arrives first, and "drop the glyph
-- if its key is HELD" fails wherever the keypress arrives
-- first, because then the key is already held at its own first
-- glyph and every fresh target is thrown away. The second is
-- what this file used to do, and it is what made the Alt-keys
-- scene deaf on the device while working in the IDE.
-- So a glyph is CLAIMED instead: one per press, released at
-- keyup (spendGlyph below). That question -- has this key's
-- glyph been judged since its last release -- has the same
-- answer in both orders.
-- An Alt+key chord is swallowed by the alt+* shortcut AND its
-- glyph dropped in appTextinput (a chord glyph CAN surface and
-- is never a target), so a chord cannot fumble a target. The
-- release boundary still leaks: a final key-repeat glyph can
-- arrive just after its keyup, so a key stays spent for a frame
-- after release (INPUT.upRecent, ours -- the keyboard reports
-- the key up the moment it is released, so nothing else marks
-- it recently spent).
--
-- Held modifier state is asked of the keyboard through the
-- INPUT proxy below, which folds the l/r pairs via Key. It used
-- to be a mirror this file maintained on every press and
-- release, and then a read of a set the framework tracked; the
-- framework tracks nothing now (Decision 30) and the device is
-- the answer outside an event -- which is what the key-cap
-- renderer needs, since it reads INPUT.shift from draw, where
-- there is no event argument to consult.


-- Reads ask Key, which folds each l/r modifier pair the way a
-- combo string does (doc/input_api.md, "Held keys"). Only
-- `upRecent` is ours.
INPUT = setmetatable({ upRecent = { } }, {
  __index = function(_, k)
    ---> REMARK: WHY WOULD WE DO IT AND WHY USE custom 'INPUT' at all?
    if k == "shift" then return Key.shift() end
    if k == "ctrl" then return Key.ctrl() end
    if k == "alt" then return Key.alt() end
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
  --> REMARK: what is it for? (setTextInput)
  love.keyboard.setTextInput(true)
  INPUT.upRecent = { }
  GLYPH_CLAIMED = { }
  compy.input.hooks.keypressed = appKeypressed
  compy.input.hooks.keyreleased = appKeyreleased
  compy.input.hooks.textinput = appTextinput
  register_reserved()
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

-- One glyph per key press reaches a scene. textinput carries no
-- isrepeat flag of its own, so a repeat has to be recognised
-- some other way, and the held set cannot do it: whether
-- keypressed or textinput arrives first is not fixed
-- (doc/development/internals/user_input.md, "Data flow" -- no
-- ordering guarantee between the two channels), so at a FRESH
-- glyph the producing key is already held on one build and not
-- yet held on another. Asking "is it held" therefore answers
-- the environment, not the question.
--
-- Claiming answers the real one, the same way in both orders:
-- has a glyph for this key already been judged since its last
-- release. Claims are dropped on keyup (appKeyreleased), so the
-- next press starts clean.
GLYPH_CLAIMED = { }

-- Claim this key's glyph for the current press. True means the
-- caller must DROP it: either a glyph was already claimed (a
-- key-repeat), or the key came up within INPUT_UP_GRACE frames
-- and this is a final repeat trailing just after keyup.
-- Keypresses do not use this: they have the real isrepeat flag.
function spendGlyph(k)
  if GLYPH_CLAIMED[k] then return true end
  local up = INPUT.upRecent[k]
  if up and DBG_FRAME - up <= INPUT_UP_GRACE then return true end
  GLYPH_CLAIMED[k] = true
  return false
end

-- isr is the API's isrepeat (third hook argument): a held key
-- is filtered at the source instead of inferred from held
-- state. capslock is exempt because its release may not
-- arrive, so its next press can come in flagged as a repeat,
-- and dropping that would freeze the Caps estimate on a lock
-- the player did toggle (see the Caps Lock section of
-- doc/development/internals/examples/keyboard.md). Scene input
-- is also dropped while the help overlay is up (the game is
-- frozen behind it).
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
  GLYPH_CLAIMED[k] = nil
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
