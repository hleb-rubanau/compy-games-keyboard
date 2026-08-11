-- Shared difficulty-notch core. Per-scene notch value, teacher
-- chord shift saturating at the scene's declared bounds, and
-- configured defaults at program start. Every exercise drives
-- the notch by teacher chord, with the re-entry policy below.

NOTCH = { }

function notchInit()
  for _, id in ipairs(MENU_ORDER) do
    NOTCH[id] = NOTCH_START[id] or 0
  end
end

function notchGet(id)
  return NOTCH[id] or 0
end

function notchShift(id, delta, lo, hi)
  local v = (NOTCH[id] or 0) + delta
  if v < lo then v = lo end
  if v > hi then v = hi end
  NOTCH[id] = v
  return v
end

-- Re-entry policy for player-facing-notch games: a climbed
-- notch (>= 0) resets to 0 each fresh entry (a clean climb),
-- but an eased notch (< 0, set by the teacher or reached by
-- struggling) is preserved -- min(notch, 0). Teacher-only-notch
-- games skip this and keep their notch.
function notchEnterReset(id)
  NOTCH[id] = math.min(NOTCH[id] or 0, 0)
end
