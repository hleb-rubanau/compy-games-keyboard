-- Deliberate pause for the TIMED games. (UX standard: a timed
-- game keeps things happening while the child is away, so it
-- offers a pause.) Alt+P toggles a modal freeze on a scene
-- that sets `timed = true` (Hunt); the untimed find-key drills
-- have no timer and no pause. While paused the game gets no
-- updates (state kept; the child controls resume) and a modal
-- overlay shows the resume chord as keycaps for non-readers.

PAUSED = false

-- Only a timed scene pauses; Alt+P is a no-op elsewhere.
function pauseToggle()
  local s = SCENES[ACTIVE]
  if not (s and s.timed) then return end
  PAUSED = not PAUSED
  SOUND.pause()
end

-- Cleared on each scene entry; pause never leaks across games.
function pauseClear()
  PAUSED = false
end

-- The resume chord (Alt + P) as two centered keycaps.
function pauseDrawKeys()
  local h = 56
  local u = h / KB_STD_H
  local wa = KB_SMALL_W * u
  local wp = KB_STD_W * u
  local gap = 12
  local x = (REF_W - wa - wp - gap) / 2
  drawKeycap({ x = x, y = 292, w = wa, h = h },
    { name = "lalt", unit = u })
  drawKeycap({ x = x + wa + gap, y = 292, w = wp, h = h },
    { name = "p", unit = u })
end

function drawPauseOverlay()
  gfx.setColor(COL_OVERLAY)
  gfx.rectangle("fill", 0, 0, REF_W, REF_H)
  drawBandText(STR.paused, { 150, 230 },
    getFont(FONT_HEAD), COL_TEXT)
  pauseDrawKeys()
  drawBandText(STR.back_hint, { 366, 402 },
    getFont(FONT_STATUS), COL_DIM)
end
