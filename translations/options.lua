-- The two options (the language, and whether the helper collects) and the page on
-- Options > AddOns > Translations.

local Config = Translations.Config
local Store = Translations.Store

local Options = {}
Translations.Options = Options

local options = hafen.client():options():addon()
Options.language = options:text("language"):default(Config.ENGLISH):add()
Options.helper = options:boolean("helper"):default(false):add()

local languageDropdown -- the page's, while the page is up

-- The page's dropdown is in a character's tree: call this from the step only.
function Options.syncLanguage() -- the rows and the pick follow the file and the option
    if languageDropdown and languageDropdown:exists() then
        languageDropdown:rows(Store.languageRows())
        languageDropdown:value(Options.language:value())
    end
end

options:panel(function(root)
    root:gap(4)
    hafen.ui():label():parent(root):text("Language")
    languageDropdown = hafen.ui():dropdown():parent(root):size(160)
        :rows(Store.languageRows()):value(Options.language:value())
    languageDropdown:on("Changed", function(name) Options.language:value(name) end)

    local helperCheck = hafen.ui():check():parent(root)
        :text("Translation helper: collect the strings the language does not name yet"):bind(Options.helper)
    local openButton = hafen.ui():button():parent(root):size(Config.OPEN_BUTTON_WIDTH):text("Open the translator")
        :enabled(Options.helper:value())
    helperCheck:on("Changed", function(on) openButton:enabled(on) end)
    -- A press runs inside the character's tree, so the window is opened on the step. window.lua loads
    -- after this file: resolved when pressed.
    openButton:on("Pressed", function() hafen.timer():after(0, Translations.Window.open) end)
end)
