-- regex.lua -- a matcher for the patterns a catalogue carries, so the list can tell which of its strings a
-- pattern answers. The client applies a pattern as Java does; this only decides what leaves the list.
-- Whole-string match, captures by number. It reads what a translation pattern is made of:
--   literals and escapes (\. \( \\ ...), \d \w \s and their negations, . (a newline only under (?s)),
--   classes [a-z] [^0-9] with escapes inside, groups ( ) and (?: ), alternation |, the quantifiers
--   * + ? {n} {n,} {n,m} and their lazy forms, the anchors ^ $, and the flags (?s) (?i).
-- Anything else -- a lookaround, a backreference, \p{..}, a possessive quantifier -- does not compile,
-- and a row such a pattern answers stays in the list until the client redraws it.
-- It walks the subject one byte at a time, not one character: a non-ASCII letter is two to four bytes, so
-- `.` alone or {n} count differently from Java on such text; .* .+ and the classes do not.

regex = {}

local STEP_BUDGET = 5000 -- node visits per match: a pathological pattern gives up, never stalls

-- ---------------------------------------------------------------- parsing a pattern into a tree
--
-- A node is one of: { kind = "literal", byte }, { kind = "set", test = function(byte, ignoreCase) },
-- { kind = "any" }, { kind = "start" }, { kind = "end" }, { kind = "group", alternatives, capture }.
-- A sequence is an array of { node, minimum, maximum, lazy }; alternatives are an array of sequences.

local function parse(source)
    local position = 1
    local groupCount = 0
    local flags = { s = false, i = false }
    local parseAlternatives -- defined below; a group parses its inside with it

    local function peek(length)
        return string.sub(source, position, position + (length or 1) - 1)
    end

    local function take()
        local byte = string.sub(source, position, position)
        position = position + 1
        return byte
    end

    local function unsupported()
        error("unsupported")
    end

    -- After a backslash: a literal, or a class.
    local function escape()
        local byte = take()
        if byte == "d" then
            return { kind = "set", test = function(candidate) return string.find(candidate, "%d") ~= nil end }
        elseif byte == "D" then
            return { kind = "set", test = function(candidate) return string.find(candidate, "%d") == nil end }
        elseif byte == "w" then
            return { kind = "set", test = function(candidate) return string.find(candidate, "[%w_]") ~= nil end }
        elseif byte == "W" then
            return { kind = "set", test = function(candidate) return string.find(candidate, "[%w_]") == nil end }
        elseif byte == "s" then
            return { kind = "set", test = function(candidate) return string.find(candidate, "%s") ~= nil end }
        elseif byte == "S" then
            return { kind = "set", test = function(candidate) return string.find(candidate, "%s") == nil end }
        elseif byte == "t" then
            return { kind = "literal", byte = "\t" }
        elseif byte == "n" then
            return { kind = "literal", byte = "\n" }
        elseif byte == "r" then
            return { kind = "literal", byte = "\r" }
        elseif byte == "" or string.find(byte, "%w") then
            unsupported() -- \b \p \1 \Q and every other letter or digit
        end
        return { kind = "literal", byte = byte } -- an escaped punctuation mark is itself
    end

    -- After "[": ranges, single bytes and escapes up to the "]".
    local function characterClass()
        local negated = false
        if peek() == "^" then
            negated = true
            take()
        end
        local items = {}
        local first = true
        while true do
            local byte = take()
            if byte == "" or byte == "[" then
                unsupported() -- unclosed, nested, or [a&&[b]]
            end
            if byte == "]" and not first then
                break
            end
            local low
            if byte == "\\" then
                local escaped = escape()
                if escaped.kind == "set" then
                    items[#items + 1] = { test = escaped.test }
                else
                    low = escaped.byte
                end
            else
                low = byte
            end
            if low then
                if peek() == "-" and peek(2) ~= "-]" and position < #source then -- a range
                    take()
                    local high = take()
                    if high == "\\" then
                        local escaped = escape()
                        if escaped.kind ~= "literal" then
                            unsupported()
                        end
                        high = escaped.byte
                    end
                    items[#items + 1] = { low = low, high = high }
                else
                    items[#items + 1] = { low = low, high = low }
                end
            end
            first = false
        end
        local function test(byte, ignoreCase)
            local function hit(candidate)
                for _, item in ipairs(items) do
                    if item.test then
                        if item.test(candidate) then
                            return true
                        end
                    elseif candidate >= item.low and candidate <= item.high then
                        return true
                    end
                end
                return false
            end
            local found = hit(byte) or (ignoreCase and (hit(string.lower(byte)) or hit(string.upper(byte))))
            if negated then
                return not found
            end
            return found
        end
        return { kind = "set", test = test }
    end

    -- One node, or nil for a flag group, which sets the flags and stands for nothing.
    local function atom()
        local byte = take()
        if byte == "(" then
            local capture
            if peek(2) == "?:" then
                take()
                take()
            elseif peek() == "?" then -- (?s) (?i) (?si): a flag group, and nothing else
                take()
                local letters = ""
                while string.find(peek(), "^[a-z]") do
                    letters = letters .. take()
                end
                if letters == "" or take() ~= ")" then
                    unsupported()
                end
                for letter in string.gmatch(letters, ".") do
                    if letter ~= "s" and letter ~= "i" then
                        unsupported()
                    end
                    flags[letter] = true
                end
                return nil
            else
                groupCount = groupCount + 1
                capture = groupCount
            end
            local alternatives = parseAlternatives()
            if take() ~= ")" then
                unsupported()
            end
            return { kind = "group", alternatives = alternatives, capture = capture }
        elseif byte == "[" then
            return characterClass()
        elseif byte == "." then
            return { kind = "any" }
        elseif byte == "^" then
            return { kind = "start" }
        elseif byte == "$" then
            return { kind = "end" }
        elseif byte == "\\" then
            return escape()
        elseif byte == "*" or byte == "+" or byte == "?" or byte == "{" or byte == ")" or byte == "" then
            unsupported()
        end
        return { kind = "literal", byte = byte }
    end

    -- The nodes up to a "|", a ")" or the end, each with its quantifier.
    local function sequence()
        local items = {}
        while true do
            local byte = peek()
            if byte == "" or byte == "|" or byte == ")" then
                break
            end
            local node = atom()
            if node then
                local minimum, maximum = 1, 1
                local quantifier = peek()
                if quantifier == "*" then
                    minimum, maximum = 0, nil
                    take()
                elseif quantifier == "+" then
                    minimum, maximum = 1, nil
                    take()
                elseif quantifier == "?" then
                    minimum, maximum = 0, 1
                    take()
                elseif quantifier == "{" then
                    local low, comma, high, after = string.match(source, "^{(%d+)(,?)(%d*)}()", position)
                    if not low then
                        unsupported()
                    end
                    minimum = tonumber(low)
                    if comma == "" then
                        maximum = minimum
                    elseif high == "" then
                        maximum = nil
                    else
                        maximum = tonumber(high)
                    end
                    position = after
                end
                local lazy = false
                if quantifier == "*" or quantifier == "+" or quantifier == "?" or quantifier == "{" then
                    if peek() == "?" then
                        lazy = true
                        take()
                    elseif peek() == "+" then
                        unsupported() -- a possessive quantifier
                    end
                end
                items[#items + 1] = { node = node, minimum = minimum, maximum = maximum, lazy = lazy }
            end
        end
        return items
    end

    parseAlternatives = function()
        local alternatives = { sequence() }
        while peek() == "|" do
            take()
            alternatives[#alternatives + 1] = sequence()
        end
        return alternatives
    end

    local tree = parseAlternatives()
    if position <= #source then
        unsupported() -- a ")" with no "(" before it
    end
    return { tree = tree, flags = flags, groups = groupCount }
end

--- Compile a Java regular expression, or nil where it uses something this matcher does not read.
function regex.compile(source)
    local ok, program = pcall(parse, source)
    if ok then
        return program
    end
    return nil
end

-- ---------------------------------------------------------------- matching
--
-- Backtracking by continuation: every matcher takes `rest`, the function that matches what follows, and
-- answers what `rest` answers -- the captures on success, nil on failure -- so an alternative or a
-- repetition that fails further on is simply tried the next way.

--- Match the whole of subject. Returns the captures by group number (an empty table for none), or nil.
function regex.matches(program, subject)
    local flags = program.flags
    local length = #subject
    local steps = 0
    local matchAlternatives, matchSequence -- defined below; a group and a repetition recurse through them

    local function matchNode(node, position, captures, rest)
        steps = steps + 1
        if steps > STEP_BUDGET then
            error("budget")
        end
        local kind = node.kind
        if kind == "literal" then
            local byte = string.sub(subject, position, position)
            if byte == "" then
                return nil
            end
            if byte ~= node.byte and not (flags.i and string.lower(byte) == string.lower(node.byte)) then
                return nil
            end
            return rest(position + 1, captures)
        elseif kind == "set" then
            local byte = string.sub(subject, position, position)
            if byte == "" or not node.test(byte, flags.i) then
                return nil
            end
            return rest(position + 1, captures)
        elseif kind == "any" then
            local byte = string.sub(subject, position, position)
            if byte == "" or (byte == "\n" and not flags.s) then
                return nil
            end
            return rest(position + 1, captures)
        elseif kind == "start" then
            if position == 1 then
                return rest(position, captures)
            end
            return nil
        elseif kind == "end" then
            if position == length + 1 then
                return rest(position, captures)
            end
            return nil
        end
        -- a group: what it matched is capture `node.capture`, copied so a failed branch leaves nothing behind
        return matchAlternatives(node.alternatives, position, captures, function(after, innerCaptures)
            if node.capture then
                local copy = {}
                for group, value in pairs(innerCaptures) do
                    copy[group] = value
                end
                copy[node.capture] = string.sub(subject, position, after - 1)
                innerCaptures = copy
            end
            return rest(after, innerCaptures)
        end)
    end

    local function matchRepetition(item, count, position, captures, rest)
        local function oneMore()
            if item.maximum ~= nil and count >= item.maximum then
                return nil
            end
            return matchNode(item.node, position, captures, function(after, innerCaptures)
                if after == position and count >= item.minimum then
                    return nil -- an empty pass past the minimum never ends
                end
                return matchRepetition(item, count + 1, after, innerCaptures, rest)
            end)
        end
        if count < item.minimum then
            return oneMore()
        end
        if item.lazy then
            return rest(position, captures) or oneMore()
        end
        return oneMore() or rest(position, captures)
    end

    matchSequence = function(items, index, position, captures, rest)
        if index > #items then
            return rest(position, captures)
        end
        return matchRepetition(items[index], 0, position, captures, function(after, innerCaptures)
            return matchSequence(items, index + 1, after, innerCaptures, rest)
        end)
    end

    matchAlternatives = function(alternatives, position, captures, rest)
        for _, items in ipairs(alternatives) do
            local result = matchSequence(items, 1, position, captures, rest)
            if result then
                return result
            end
        end
        return nil
    end

    local ok, result = pcall(matchAlternatives, program.tree, 1, {}, function(position, captures)
        if position == length + 1 then
            return captures
        end
        return nil
    end)
    if not ok then
        return nil -- over budget: not a match the list will claim
    end
    return result
end

--- The string as a regular expression that matches exactly itself: Java's special characters escaped.
function regex.quote(text)
    return (string.gsub(text, "[\\%^%$%.%|%?%*%+%(%)%[%]%{%}]", "\\%0"))
end
