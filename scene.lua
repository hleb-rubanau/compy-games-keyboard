-- Scene registry and dispatch. The intro and menu load once at
-- boot; the mini-games are lazy-loaded the first time they are
-- entered (the device is low-end, so boot stays light). A game
-- is loaded by dofile'ing its file once, which registers its
-- handler table; scenes are never re-loaded on re-entry.

SCENES = { }
ACTIVE = nil

-- id -> source file for a lazy-loaded game.
SCENE_FILE = { }
SCENE_LOADED = { }

-- Files already dofile'd, by path. A game whose behaviour lives
-- in a shared engine loads it with ensureFile at the top of its
-- own file, so the engine arrives once however the child reaches
-- it -- and a game never has to load another game to borrow it.
LOADED_FILES = { }

function ensureFile(file)
  if LOADED_FILES[file] then return end
  LOADED_FILES[file] = true
  dofile(file)
end

MENU_INDEX = { }
for i, id in ipairs(MENU_ORDER) do
  MENU_INDEX[id] = i
end

function registerScene(id, handlers)
  SCENES[id] = handlers
end

-- A game is present in this build iff its file is registered;
-- the menu derives its list from this, without loading code.
function sceneAvailable(id)
  return SCENE_FILE[id] ~= nil
end

function ensureScene(id)
  if SCENE_LOADED[id] then return end
  local file = SCENE_FILE[id]
  if file then
    ensureFile(file)
    SCENE_LOADED[id] = true
  end
end

function gotoScene(id)
  ensureScene(id)
  ACTIVE = id
  -- Default background; a pastel scene overrides it in enter().
  pastelClear()
  pauseClear()
  local s = SCENES[id]
  if s and s.enter then s.enter() end
end

function isGameScene(id)
  return MENU_INDEX[id] ~= nil
end

function sceneUpdate(dt)
  local s = SCENES[ACTIVE]
  if s and s.update then s.update(dt) end
end

function sceneDraw()
  local s = SCENES[ACTIVE]
  if s and s.draw then s.draw() end
end
