-- keyboard: the program a 4-6 year-old launches to meet the
-- keyboard. One program: a typewriter intro, a mini-game menu,
-- and the mini-games. main.lua defines update/draw and loads
-- the scenes once here at boot; the keyboard/text callbacks are
-- compy.input hooks and shortcuts, registered in input.lua.

gfx = love.graphics

-- Debug logging. When DEBUG is on, diagnostics go to a log file
-- in the save dir (read via adb), not an on-screen overlay.
-- update/draw also run under pcall, so a thrown frame is logged
-- and recovered (the outer gfx.pop still runs, no stack leak)
-- instead of freezing or crashing, so the app stays runnable
-- while the problem is captured. Set DEBUG = false to ship.
DEBUG = false
DBG_LOG = "keyboard-debug.log"
DBG_FRAME = 0
DBG_LASTERR = nil

function dbgLog(msg)
  if not DEBUG then return end
  local line = DBG_FRAME .. " " .. msg
  print("[KBD] " .. line)
  pcall(love.filesystem.append, DBG_LOG, line .. "\n")
end

-- Log a thrown error once (deduped) so a per-frame throw does
-- not spam the log.
function dbgLogErr(where, err)
  if err == DBG_LASTERR then return end
  DBG_LASTERR = err
  dbgLog(where .. " ERR @ " .. tostring(ACTIVE)
    .. ": " .. tostring(err))
end

-- Reset the log + record the save dir (pcall'd at boot so a
-- restricted filesystem can never block startup). Read logs via
-- `adb logcat | grep KBD` -- the save dir is not pullable under
-- Android scoped storage.
function dbgBoot()
  love.filesystem.write(DBG_LOG, "=== boot ===\n")
  dbgLog("save dir " .. love.filesystem.getSaveDirectory())
end

-- Shared infrastructure plus the two scenes needed at boot
-- (intro, menu). Mini-games are lazy-loaded on first entry.
dofile("config.lua")
dofile("pastel.lua")
dofile("locale.lua")
dofile("layout.lua")
dofile("sound.lua")
dofile("keyboard_view.lua")
dofile("indicators.lua")
dofile("notch.lua")
dofile("gauge.lua")
dofile("scene.lua")
dofile("input.lua")
dofile("help.lua")
dofile("pause.lua")
dofile("firework.lua")
dofile("findkey.lua")
dofile("hints.lua")
dofile("intro.lua")
dofile("menu.lua")

-- Games present in this build (lazy-loaded). Adding a slice
-- registers its file here; the menu picks it up structurally.
SCENE_FILE.press = "press.lua"
SCENE_FILE.find = "find.lua"
SCENE_FILE.hunt = "hunt.lua"
SCENE_FILE.alt = "alt.lua"

notchInit()
inputInit()
if DEBUG then pcall(dbgBoot) end
gotoScene("intro")

-- Hold ticks until the first frame is drawn, and cap dt, so a
-- slow boot or GC spike never leaks into the first update or
-- fast-forwards an animation (e.g. the intro typing) at once.
-- DREW_ONCE flips true at the end of the first love.draw.
DREW_ONCE = false
MAX_DT = 0.1

function updateStep(dt)
  if not DREW_ONCE then return end
  if dt > MAX_DT then dt = MAX_DT end
  -- The pastel background eases every frame, even while a help
  -- overlay pauses the game underneath.
  pastelTick(dt)
  -- A modal pause (Alt+P, timed games only) or an open help
  -- overlay (held Alt+H) freezes the active game; it resumes on
  -- dismiss.
  if PAUSED then return end
  if helpOverlayShown() then return end
  sceneUpdate(dt)
end

function love.update(dt)
  DBG_FRAME = DBG_FRAME + 1
  if not DEBUG then return updateStep(dt) end
  local ok, err = pcall(updateStep, dt)
  if not ok then dbgLogErr("UPDATE", err) end
end

-- Draw in the 960x540 reference canvas, scaled uniformly and
-- centered to the real resolution. Nothing scrolls.
function drawStep()
  sceneDraw()
  if PAUSED then
    drawPauseOverlay()
  else
    drawHelpLayer()
  end
end

function love.draw()
  pastelDrawBg()
  local w, h = gfx.getDimensions()
  local s = math.min(w / REF_W, h / REF_H)
  gfx.push()
  gfx.translate((w - REF_W * s) / 2, (h - REF_H * s) / 2)
  gfx.scale(s, s)
  if not DEBUG then
    drawStep()
  else
    local ok, err = pcall(drawStep)
    if not ok then dbgLogErr("DRAW", err) end
  end
  gfx.pop()
  DREW_ONCE = true
end

-- Keyboard/text handlers are registered as compy.input.hooks in
-- inputInit (input.lua), not as love.* globals: the framework
-- captures love.* into the same hooks, so the explicit form
-- only drops three wrappers that existed to satisfy LOVE's
-- naming convention.
