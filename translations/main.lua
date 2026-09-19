-- Entry point: the harvest timer, the helper option, and the language at load.

local Config = Translations.Config
local Store = Translations.Store
local Options = Translations.Options
local Catalogue = Translations.Catalogue
local Languages = Translations.Languages
local Window = Translations.Window

-- Every second: what the client drew and the language did not name goes into the list.
hafen.timer():every(1, function()
    if Catalogue.harvest() > 0 then
        Window.refresh()
    end
end)

-- Helper on: a fresh miss round, so the set holds what is drawn from now on. Off: the window goes. The tick
-- is answered inside the options page's tree, so the window is destroyed on the step.
Options.helper:on("Changed", function(on)
    if on then
        if Catalogue.language then
            Catalogue.startMissRound()
        end
    else
        hafen.timer():after(0, Window.destroy)
    end
end)

-- The language the option names may have been deleted since the addon last ran. Checked before Changed is
-- wired, so the reset does not apply twice.
if Options.language:value() ~= Config.ENGLISH and not Store.isLanguage(Options.language:value()) then
    Options.language:value(Config.ENGLISH)
end
Options.language:on("Changed", Languages.apply)
Languages.apply(Options.language:value())
if Store.settings.windowOpen and Options.helper:value() then
    Window.build()
end
