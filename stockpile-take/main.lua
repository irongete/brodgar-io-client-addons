-- Stockpile Take: an amount field and a Take button below the pile in every Stockpile window.
--
-- Both controls are parented to the window, so window:pack() grows its frame around them and everything
-- the client already placed there keeps its position. Take sends one "xfer" per item on a timer, the
-- message a shift-click on the pile sends.

local GAP = 4                    -- design pixels between the pile's box and the row, and between the controls
local AMOUNT_FIELD_WIDTH = 48    -- the Take button takes the rest of the box's width
local WITHDRAW_INTERVAL = 0.05   -- seconds between two withdrawals
local MOST_PER_PRESS = 500       -- upper bound for one press, whatever the field says

local watchByAccount = {}        -- [account] = the widget subscription standing on that character's tree

-- One item, then the next, until the count runs out or the window closes under it.
local function withdrawNext(pileBox, remaining)
  if (remaining <= 0) or not pileBox:exists() then return end
  local sent, failure = pcall(function() pileBox:send("xfer") end)
  if not sent then
    hafen.log():write("stockpile-take: " .. tostring(failure))
    return
  end
  hafen.timer():after(WITHDRAW_INTERVAL, function() withdrawNext(pileBox, remaining - 1) end)
end

-- Builds the row under `pileBox`, the ISBox that holds the pile, inside the window carrying it.
local function addControls(pileBox)
  local window = pileBox:parent()
  if not (window and window:is("window")) then return end
  -- A new subscription rescans the whole tree as it registers; the button's name marks a window already done.
  if window:matchAll("[name=stockpile-take/take]")[1] then return end

  local pilePosition, pileSize = pileBox:position(), pileBox:size()
  local rowY = pilePosition.y + pileSize.h + GAP

  local amountField = hafen.ui():entry():parent(window):size(AMOUNT_FIELD_WIDTH):value("1")
    :tooltip("how many items to take out of this pile")
  local takeButton = hafen.ui():button():parent(window):size(pileSize.w - AMOUNT_FIELD_WIDTH - GAP)
    :name("take"):text("Take"):tooltip("take that many items out of this pile")

  -- Each control is its own art's height; the shorter one is centred against the taller.
  local heightDifference = math.floor((takeButton:size().h - amountField:size().h) / 2)
  amountField:position(pilePosition.x, rowY + math.max(0, heightDifference))
  takeButton:position(pilePosition.x + AMOUNT_FIELD_WIDTH + GAP, rowY + math.max(0, -heightDifference))
  window:pack()

  local function take()
    local amount = math.floor(tonumber(amountField:value() or "") or 0)
    if amount < 1 then
      hafen.log():write("stockpile-take: type how many items to take out first")
      return
    end
    withdrawNext(pileBox, math.min(amount, MOST_PER_PRESS))
  end

  takeButton:on("Pressed", take)
  amountField:on("Submitted", take)
end

-- One subscription per character's tree, so every login needs its own. The selector is chained because a
-- window is hung before its contents arrive and its caption can land later still: it fires once both hold.
-- SessionEnteredWorld fires again for the same session when it takes another character, hence the replace.
local function watchStockpiles(session)
  local previous = watchByAccount[session:user()]
  if previous then previous:off() end
  watchByAccount[session:user()] =
    session:ui():on("window[title=Stockpile] @ISBox", "Added", addControls)
end

hafen.event():on("SessionEnteredWorld", watchStockpiles)
hafen.event():on("SessionRemoved", function(session) watchByAccount[session:user()] = nil end)
