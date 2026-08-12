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
-- flow"), and nothing here may depend on which arrives first.
-- Two schemes are ruled out by that: "a fresh keypress arms a
-- gate, its textinput consumes it" fails wherever the glyph
-- arrives first, and "drop the glyph if its key is HELD" fails
-- wherever the keypress arrives first, because then the key is
-- already held at its own first glyph and every fresh target is
-- thrown away. The second is what this file used to do, and it
-- is what made the Alt-keys scene deaf.
-- So a glyph is CLAIMED instead: one per press. The claim asks
-- a question with the same answer in both orders -- has a glyph
-- for this key been taken since the key was last down -- and it
-- is released by asking the KEYBOARD, once a frame (inputTick),
-- rather than by any event. There is no grace window and no
-- frame clock: the previous version kept a key spent for a
-- frame after keyup to swallow a trailing repeat glyph, and paid
-- for it by dropping a genuinely fast tap.
-- An Alt+key chord is swallowed by the alt+* shortcut, which
-- also claims the chord's trigger, AND its glyph is dropped in
-- appTextinput (a chord glyph CAN surface and is never a
-- target), so a chord cannot fumble a target -- including the
-- case where the modifier is released first and the trigger
-- keeps repeating on its own.
--
-- Held modifier state is asked of the keyboard through Key,
-- which folds each l/r pair the way a combo string does. It
-- used to be a mirror this file maintained on every press and
-- release, and then a read of a set the framework tracked; the
-- framework tracks nothing now (Decision 30) and the device is
-- the answer outside an event -- which is what the key-cap
-- renderer needs, since it reads that state from draw, where
-- there is no event argument to consult.

-- A chord's trigger key is claimed when the chord is taken, so a
-- trigger still down after its modifier is released cannot type
-- into the scene: Alt+H then letting go of Alt leaves H
-- repeating, and those glyphs are not a typed answer. Claiming
-- costs nothing on a repeat -- the claim is already held -- and
-- it is released by the same poll as any other (inputTick).
local function claimChord(k)
  spendGlyph(k)
end

-- The app's reserved keys, none of which reaches the scene.
--
-- stop_here is what says a combo is taken, so the action itself
-- does not have to know what happens after it returns.
-- ignore_repeat goes inside it wherever there IS an action,
-- because stop_here alone re-runs the action on every OS
-- repeat: a held ctrl+alt+up would ramp the notch every frame.
-- The CLAIM is outside it: an action fires once per press, a
-- claim must stand for as long as the key is down.
--
-- "alt+*" is the whole Alt class: every Alt chord is swallowed,
-- never reaching the scene as a typed target. Its only job is
-- the claim.
-- alt+p is an exact binding and exact wins over the class, so it
-- claims for itself.
-- Ctrl+Alt+H is NOT in the class -- a different modifier set is
-- a different class -- which is the "and not Ctrl" test this
-- file used to write out by hand before combo classes existed.
--
-- A combo is its modifier set EXACTLY, where the hand-written
-- tests these replaced were one-sided: "shift and not ctrl" also
-- accepted Alt, and "ctrl and alt" also accepted Shift. Each
-- gesture is therefore bound twice, to the same handler, so
-- Alt+Shift+Esc still goes back and Ctrl+Alt+Shift+Up still
-- notches. Binding the value twice is the whole cost.
local function register_reserved()
  local fn = compy.input.fn
  local sc = compy.input.shortcuts.keypressed
  local back = fn.stop_here(fn.ignore_repeat(goBack))
  local notch_up = fn.stop_here(fn.ignore_repeat(function()
    notchAdjust(1)
  end))
  local notch_down = fn.stop_here(fn.ignore_repeat(function()
    notchAdjust(-1)
  end))
  sc["shift+escape"] = back
  sc["alt+shift+escape"] = back
  sc["ctrl+alt+up"] = notch_up
  sc["ctrl+alt+shift+up"] = notch_up
  sc["ctrl+alt+down"] = notch_down
  sc["ctrl+alt+shift+down"] = notch_down
  sc["alt+*"] = fn.stop_here(claimChord)
  sc["alt+p"] = fn.stop_here(function(k, _, isr)
    claimChord(k)
    if not isr then pauseToggle() end
  end)
end

function inputInit()
  --> REMARK: what is it for? (setTextInput)
  love.keyboard.setTextInput(true)
  GLYPH_CLAIMED = { }
  compy.input.hooks.keypressed = appKeypressed
  compy.input.hooks.keyreleased = appKeyreleased
  compy.input.hooks.textinput = appTextinput
  register_reserved()
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
-- has a glyph for this key already been judged since the key was
-- last down.
GLYPH_CLAIMED = { }

-- The key a produced character came from: space, a shifted
-- symbol through SHIFT_MAP inverted, a letter its lowercase key,
-- else itself. Both textinput scenes need it and it lives here
-- because scene files are lazy-loaded -- config.lua, which holds
-- SHIFT_MAP, is loaded long before this one.
GLYPH_BASE = { }
for base, sym in pairs(SHIFT_MAP) do
  GLYPH_BASE[sym] = base
end

function glyphBaseKey(ch)
  if ch == " " then return "space" end
  if GLYPH_BASE[ch] then return GLYPH_BASE[ch] end
  if isAlphaChar(ch) then return string.lower(ch) end
  return ch
end

-- love.keyboard.isDown RAISES on a string that is not one of
-- LOVE's key constants -- "Invalid key constant: ~" -- and a
-- produced character is not always the name of a key: an IME or
-- dead-key composition can map to nothing this keyboard has.
-- A claim that cannot be polled cannot be released, so it is
-- never taken: that character is accepted, and holding one would
-- repeat it. No scene targets such a character, and the
-- alternative is a per-frame loop that can raise. Asked once per
-- key name and remembered, since the answer cannot change.
local POLLABLE = { }
local function pollable(k)
  local known = POLLABLE[k]
  if known == nil then
    known = pcall(love.keyboard.isDown, k)
    POLLABLE[k] = known
  end
  return known
end

-- Claim this key's glyph for the current press. True means the
-- caller must DROP it: a glyph for this key has already been
-- taken and the key has not been up since.
-- Keypresses do not use this: they have the real isrepeat flag.
function spendGlyph(k)
  if GLYPH_CLAIMED[k] then return true end
  if not pollable(k) then return false end
  GLYPH_CLAIMED[k] = true
  return false
end

-- Claims are released by the DEVICE, once a frame, and by
-- nothing else. keyreleased is not consulted, which is the point:
-- a release and a trailing repeat glyph are the same shape on
-- that channel, so clearing at the release lets the trailing
-- glyph through as a fresh one -- a wrong answer nobody typed,
-- which is what the frame-stamped grace window used to swallow.
-- Asking the keyboard needs no window, no clock and no
-- ordering: whether the key is down is a frame-time question
-- about physical state, which is the rung this is for
-- (doc/input_api.md, "Held keys"). Key.any_pressed(k) is the
-- platform's form of this call and is what a Compy project
-- should reach for; love.keyboard.isDown is kept here because
-- this game asks it directly elsewhere too (helpHeld).
function inputTick()
  for k in pairs(GLYPH_CLAIMED) do
    if not love.keyboard.isDown(k) then
      GLYPH_CLAIMED[k] = nil
    end
  end
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
  -- A bare Alt press reaches here where it used to be swallowed:
  -- the hand-written chord test caught it (Alt was held, and the
  -- key WAS Alt), while "alt+*" cannot -- a modifier's own press
  -- names no combo. Scenes ignore modifiers, but the intro
  -- finishes its typewriter on any key, so without this Alt alone
  -- would skip it. Lone Shift does skip it, here as upstream:
  -- that asymmetry is the game's, and is left alone.
  if Key.is_alt(k) then return end
  local s = SCENES[ACTIVE]
  if s and s.keypressed then s.keypressed(k) end
end

-- No judgement state here, by design: the claim is released by
-- inputTick's poll, not by this event. The dispatch stays --
-- bubble.lua judges its hold on this channel.
function appKeyreleased(k)
  dbgLog("KR " .. k)
  local s = SCENES[ACTIVE]
  if s and s.keyreleased then s.keyreleased(k) end
end

-- textinput is judged by the scene (the per-glyph stale filter
-- lives there); dropped here while paused or behind help. A
-- glyph made with Alt or Ctrl held is a chord, never a target
-- (only Shift modifies a target), so drop it too.
function appTextinput(t)
  if PAUSED then return end
  if Key.alt() then return end
  if Key.ctrl() then return end
  if helpOverlayShown() then return end
  dbgLog("TI " .. t .. " sh=" .. tostring(Key.shift()))
  if isAlphaChar(t) then
    capsReconcile(t, Key.shift())
  end
  local s = SCENES[ACTIVE]
  if s and s.textinput then s.textinput(t) end
end
