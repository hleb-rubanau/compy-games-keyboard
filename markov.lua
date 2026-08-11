-- Order-2 character Markov generator for Words and phrases.
-- Builds a context -> next-char table from the bundled corpus
-- (words_corpus.lua), normalized to the 27-symbol alphabet
-- (lowercase a-z + space), at first entry. markovWord samples a
-- letter-only word of a target length; markovPhrase joins k of
-- them with single spaces. The sampler can only emit a-z and
-- space, so a generated string never holds any other glyph.
-- MARKOV_ORDER / MARKOV_TRIES / MARKOV_CAP and the corpus are
-- loaded (config.lua, words_corpus.lua) before this file.

MARKOV = { ready = false, tab = { }, starts = { } }

-- Fold to lowercase, collapse non-letter runs to one space,
-- trim the ends, then pad with single spaces so the first and
-- last words have clean boundaries.
function markovNormalize(s)
  s = string.lower(s)
  s = s:gsub("[^a-z]+", " ")
  s = s:gsub("^ +", ""):gsub(" +$", "")
  return " " .. s .. " "
end

-- Append one observed next-char to a context's choice list.
function markovAdd(ctx, c)
  local t = MARKOV.tab[ctx]
  if not t then
    t = { }
    MARKOV.tab[ctx] = t
  end
  t[#t + 1] = c
end

-- Index every order-length window: record its next char, and at
-- each space record the following window as a word-start seed.
function markovIndex(s)
  local o = MARKOV_ORDER
  for i = 1, #s - o do
    markovAdd(s:sub(i, i + o - 1), s:sub(i + o, i + o))
    if s:sub(i, i) == " " then
      MARKOV.starts[#MARKOV.starts + 1] = s:sub(i + 1, i + o)
    end
  end
end

-- Build the table once; a second call is a no-op (idempotent).
function markovBuild()
  if MARKOV.ready then return end
  markovIndex(markovNormalize(WORDS_CORPUS))
  MARKOV.ready = true
end

-- One next char for a context, weighted by frequency (its
-- repeats in the choice list), or nil at a dead end.
function markovSample(ctx)
  local t = MARKOV.tab[ctx]
  if not t then return nil end
  return t[love.math.random(1, #t)]
end

-- Sample a single word: seed a random word-start window, then
-- append chars until a space closes the word (or the cap).
-- The leading letter run is the word.
function markovWordRaw()
  local buf = MARKOV.starts[love.math.random(1, #MARKOV.starts)]
  for _ = 1, MARKOV_CAP do
    if buf:find(" ", 1, true) then break end
    local c = markovSample(buf:sub(#buf - MARKOV_ORDER + 1))
    if not c then break end
    buf = buf .. c
  end
  return buf:match("%a+") or ""
end

-- Distance of a length from [lmin, lmax] (0 if inside).
function markovDist(n, lmin, lmax)
  if n < lmin then return lmin - n end
  if n > lmax then return n - lmax end
  return 0
end

-- Force a candidate into range: grow by more raw words until it
-- reaches lmin, then trim to lmax. Always a-z, always in range.
function markovFit(w, lmin, lmax)
  while #w < lmin do
    w = w .. markovWordRaw()
  end
  if #w > lmax then w = w:sub(1, lmax) end
  return w
end

-- A word with length in [lmin, lmax]: resample up to
-- MARKOV_TRIES times for an in-range draw, else the closest.
function markovWord(lmin, lmax)
  local best = nil
  for _ = 1, MARKOV_TRIES do
    local w = markovWordRaw()
    if #w >= lmin and #w <= lmax then return w end
    if not best or markovDist(#w, lmin, lmax)
        < markovDist(#best, lmin, lmax) then
      best = w
    end
  end
  return markovFit(best or markovWordRaw(), lmin, lmax)
end

-- True if w may join the line: not a repeat of an earlier word,
-- and not sharing the previous word's first two letters (both
-- kill the repetitive "theng the the thig" feel).
function markovDistinct(parts, w)
  for _, p in ipairs(parts) do
    if p == w then return false end
  end
  local prev = parts[#parts]
  if prev and #prev >= 2 and #w >= 2
      and prev:sub(1, 2) == w:sub(1, 2) then
    return false
  end
  return true
end

-- k words joined by single spaces; each is validated for length
-- and for variety (resampled a few times, else taken as-is).
function markovPhrase(k, lmin, lmax)
  local parts = { }
  for _ = 1, k do
    local w = markovWord(lmin, lmax)
    local t = 0
    while not markovDistinct(parts, w) and t < 12 do
      w = markovWord(lmin, lmax)
      t = t + 1
    end
    parts[#parts + 1] = w
  end
  return table.concat(parts, " ")
end
