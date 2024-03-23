--------------------------------------------------------------------------------
-- Dependencies
--------------------------------------------------------------------------------
require "json"
require "var"
require "wait"


--------------------------------------------------------------------------------
-- Const
--------------------------------------------------------------------------------
Const = {
    CMD_PREFIX = "sp",
    EVENT_TRIGGER_NAME = "trigger_sound_event%d",
    EVENT_TRIGGER_RESPONSE = "Events.fire(%d)",
    EVENT_TRIGGER_SUB = 'Util.print("%s")',
    EVENT_USER_SCRIPT_NAME = "sound_event_script",
    GROUP_SOUND_EVENT = "group_sound_event",
    VERSION = "1.1.0",
}


--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------
Config = {}


function Config.get(key)
    return var["key"]
end


function Config.set(key, value)
    var["key"] = value
end


function Config.get_events_default()
    local directory = GetPluginInfo(GetPluginID(), 20)
    local path = directory .. "sc_soundpack_default.json"
    file = io.open(path, "r")
    if file == nil then
    Util.msg("Error opening config file.")
        return "[]"
    end
    contents = file:read("*a")
    file:close()
    return contents
end


function Config.get_events()
    local function sort(first, second)
        if first.group == second.group then
            return first.match < second.match
        end
        return first.group < second.group
    end
    local events = json.decode(var.events or Config.get_events_default() or "[]")
    table.sort(events, sort)
    return events
end


function Config.save_events()
    var.events = json.encode(Events.list or {})
end


function Config.get_volume()
    return tonumber(var.volume) or 100
end


function Config.set_volume(value)
    var.volume = value
end


--------------------------------------------------------------------------------
-- Sound
--------------------------------------------------------------------------------
Sound = {}


-- Allow randomizing sounds by appending "*n" to the end of a sound file name.
-- "*" indicates some randomness, and "n" denotes the number of available random
-- sounds. The actual files on disc should be named "x*1.wav", "x*2.wav", ...
-- "x*n.wav".
function Sound.get_real_file_name(sound_file)
    local random_max = sound_file:match("%*(%d+)")
    if random_max ~= nil then
        random_max = tonumber(random_max)
        local random = math.random(1, random_max)
        sound_file = sound_file:gsub("%*%d+", random)
    end
    return sound_file
end


function Sound.get_real_volume(volume)
    if volume <= 0 then
        return 0
    end
    if volume > 100 then
        volume = 100
    end
    volume = 0.4 * volume
    volume = -(40 - volume)
    return volume
end


function Sound.play_list(sounds, volume)
    for i, sound in ipairs(sounds) do
        local pause = tonumber(sound)
        if pause ~= nil then
            wait.time(pause)
        else
            Sound.play(sound, volume)
        end
    end
end


 function Sound.play(sound_file, volume)
    sound_file = Sound.get_real_file_name(sound_file)
    volume = volume or Config.get_volume()
    if volume == 0 then
        return false
    end
    volume = Sound.get_real_volume(volume)
    PlaySound(0, sound_file, false, volume)
    return true
end


--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
Events = {}


function Events.initialize()
    Events.load()
    Events.remove_all()
    Events.add_all()
end


function Events.load()
    Events.list = Config.get_events()
end


function Events.remove_all()
    local deleted = DeleteTriggerGroup(Const.GROUP_SOUND_EVENT)
    if deleted == 0 then
        return false
    end
    return true
end


function Events.add_one(id, event)
    local name = Const.EVENT_TRIGGER_NAME:format(id)
    local response = Const.EVENT_TRIGGER_RESPONSE:format(id)
    local flags = trigger_flag.Enabled + trigger_flag.KeepEvaluating
        + trigger_flag.Replace + trigger_flag.Temporary
    if event.regex then
        flags = flags + trigger_flag.RegularExpression
    end
    if event.gag then
        flags = flags + trigger_flag.OmitFromOutput
    end
    if event.sub ~= nil then
        -- Add this here rather than handling it in Events.fire()
        -- to allow users to include %1...%9 wildcards in their subs.
        local print_call = Const.EVENT_TRIGGER_SUB:format(event.sub)
        response = ("%s\n%s"):format(print_call, response)
        flags = flags + trigger_flag.OmitFromOutput
    end

    local code = AddTriggerEx(
        name, event.match,
        response, flags, custom_colour.NoChange,
        0, "", "", sendto.scriptafteromit, 100
    )

    if code ~= error_code.eOK then
        local err = error_desc[code]
        local msg = ("Failed to add trigger %s: %s."):format(name, err)
        Util.msg(msg)
        return false
    end
    code = SetTriggerOption(name, "group", Const.GROUP_SOUND_EVENT)
    if code ~= error_code.eOK then
        local err = error_desc[code]
        local msg = ("Failed to set group for trigger %s: %s."):format(name, err)
        Util.msg(msg)
    end

    return true
end


function Events.add_all()
    for i, event in ipairs(Events.list or {}) do
        Events.add_one(i, event)
    end
end


function Events.execute_user_script(script)
    local success, err = pcall(
        loadstring(script, Const.EVENT_USER_SCRIPT_NAME)
    )
    if not success then
        local msg = ("Error executing event script:\n    %s"):format(err)
        Util.msg(msg)
        return false
    end
    return true
end


function Events.fire(id)
    local event = (Events.list or {})[id]
    if event == nil then
        -- This should never be possible, but just in case.
        local msg = ("Error: event with ID %d does not exist."):format(id)
        Util.msg(msg)
        return false
    end

    if event.sounds ~= nil and #event.sounds > 0 then
        wait.make(function()
            Sound.play_list(event.sounds, event.volume)
        end)
    end
    if event.script ~= nil then
        Events.execute_user_script(event.script)
    end

    return true
end


function Events.get_groups()
    local groups = {}
    local groups_found = {}
    for i, event in ipairs(Events.list or {}) do
        local group = event.group
        if groups_found[group] == nil then
            groups_found[group] = true
            table.insert(groups, group)
        end
    end
    table.sort(groups)
    return groups
end


function Events.get_in_group(group)
    local in_group = {}
    for i, event in ipairs(Events.list or {}) do
        if event.group == group then
            table.insert(in_group, event)
        end
    end
    return in_group
end


function Events.gag(group, index, gag)
    local in_group = Events.get_in_group(group)
    local event = in_group[index]
    if event == nil then
        return false
    end
    event.gag = gag
    Config.save_events()
    Events.initialize()
    return true
end


function Events.gag_all(gag)
    for i, event in ipairs(Events.list or {}) do
        event.gag = gag
    end
    Config.save_events()
    Events.initialize()
    return true
end


function Events.sub(group, index, sub)
    local in_group = Events.get_in_group(group)
    local event = in_group[index]
    if event == nil then
        return false
    end
    event.sub = sub
    Config.save_events()
    Events.initialize()
    return true
end


--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
Command = {}

Command.list = {
    {
        name = "catch_all",
        match = "^ *" .. Const.CMD_PREFIX .. " .*$",
        script = "Command.error",
        sequence = 200,
    },
    {
        name = "version",
        match = "^ *" .. Const.CMD_PREFIX .. " +version *$",
        script = "Command.version",
    },
    {
        name = "list_groups",
        match = "^ *" .. Const.CMD_PREFIX .. " +li?st? *$",
        script = "Command.list_groups",
    },
    {
        name = "list_events",
        match = "^ *" .. Const.CMD_PREFIX .. " +li?st? +(?<group>\\w+) *$",
        script = "Command.list_events",
    },
    {
        name = "display_event",
        match = "^ *" .. Const.CMD_PREFIX .. " +li?st? +(?<group>[a-zA-Z]+) *(?<index>\\d+) *$",
        script = "Command.display_event",
    },
    {
        name = "config_volume",
        match = "^ *" .. Const.CMD_PREFIX .. " +vol(?:ume)? +(?<value>\\d+) *$",
        script = "Command.set_volume",
    },
    {
        name = "gag_event",
        match = "^ *" .. Const.CMD_PREFIX .. " +gag +(?<group>[a-zA-Z]+) *(?<index>\\d+) +(?<setting>on|off) *$",
        script = "Command.gag_event",
    },
    {
        name = "gag_all",
        match = "^ *" .. Const.CMD_PREFIX .. " +gag +all +(?<setting>on|off) *$",
        script = "Command.gag_all",
    },
    {
        name = "sub_event",
    match = "^ *" .. Const.CMD_PREFIX .. " +sub +(?<group>[a-zA-Z]+) *(?<index>\\d+) +(?<sub>.+?) *$",
        script = "Command.sub_event",
    },
}


function Command.add_one(command)
    local flags = alias_flag.Enabled + alias_flag.IgnoreAliasCase
        + alias_flag.RegularExpression + alias_flag.Replace
        + alias_flag.Temporary
    if command.flags ~= nil then
        flags = flags + command.flags
    end
    local name = "alias_" .. command.name
    local code = AddAlias(name, command.match, "", flags, command.script or "")
    if code ~= error_code.eOK then
        local err = error_desc[code]
        local msg = ("Failed to add alias %s: %s."):format(name, err)
        Util.msg(msg)
        return false
    end
    SetAliasOption(name, "sequence", command.sequence or 100)
    return true
end


function Command.add_all()
    for i, command in ipairs(Command.list) do
        Command.add_one(command)
    end
end


function Command.error(alias, line, wc)
    Util.msg("That is not a valid command.")
end


function Command.version(alias, line, wc)
    local msg = ("Version: v%s."):format(Const.VERSION)
    Util.msg(msg)
end


function Command.list_groups(alias, line, wc)
    local groups = Events.get_groups()
    if #groups == 0 then
        Utility.msg("No event groups found.")
        return
    end

    local yellow = Util.ansi.misc.bold .. Util.ansi.fg.yellow
    local silver = Util.ansi.misc.reset .. Util.ansi.fg.grey
    local separator = ("%s, %s"):format(silver, yellow)
    local list = table.concat(groups, separator)
    Util.msg("Event groups: ", yellow, list, silver, ".")
end


function Command.list_events(alias, line, wc)
    local group = wc.group:lower()
    local in_group = Events.get_in_group(group)
    if #in_group == 0 then
        local msg = ("No %s events found."):format(group)
        Util.msg(msg)
        return
    end

    local white = Util.ansi.misc.bold .. Util.ansi.fg.grey
    local grey = Util.ansi.misc.reset .. Util.ansi.fg.grey
    local yellow = Util.ansi.misc.bold .. Util.ansi.fg.yellow
    local title = group:upper() .. " EVENTS"
    Util.print(white, title)
    Util.print(grey, string.rep("-", 80))
    for i, event in ipairs(in_group) do
        Util.print(yellow, i, grey, ". ", event.match)
    end
end


function Command.display_event(alias, line, wc)
    local group = wc.group:lower()
    local index = tonumber(wc.index)
    local in_group = Events.get_in_group(group)
    local event = in_group[index]
    if event == nil then
        local msg = ("No event %s%d found."):format(group, index)
        Util.msg(msg)
        return
    end
    local white = Util.ansi.misc.bold .. Util.ansi.fg.grey
    local yellow = Util.ansi.misc.bold .. Util.ansi.fg.yellow
    local silver = Util.ansi.misc.reset .. Util.ansi.fg.grey
    Util.print(white, group:upper(), index)
    Util.print(yellow, "Pattern", silver, ": ", event.match)
    if event.sub ~= nil then
        Util.print(yellow, "Sub", silver, ": ", event.sub)
    else
        Util.print(yellow, "Gag", silver, ": ", event.gag and "yes" or "no")
    end
    if event.sounds ~= nil and #event.sounds > 0 then
        Util.print(yellow, "Sounds", silver, ":")
        for i, sound in ipairs(event.sounds) do
            Util.print(silver, sound)
        end
    end
end


function Command.set_volume(alias, line, wc)
    local value = tonumber(wc.value)
    if value < 0 or value > 100 then
        Util.msg("Volume is between 0 and 100.")
        return
    end
    Config.set_volume(value)
    local msg = ("Master volume set to %d."):format(value)
    Util.msg(msg)
end


function Command.gag_event(alias, line, wc)
    local group = wc.group:lower()
    local index = tonumber(wc.index)
    local setting = wc.setting:lower() == "on" and true or false
    local success = Events.gag(group, index, setting)
    if not success then
        local msg = ("No event %s%d found."):format(group, index)
        Util.msg(msg)
        return
    end
    local msg = "%s gagging %s%d."
    msg = msg:format(setting and "Now" or "No longer", group, index)
    Util.msg(msg)
end


function Command.gag_all(alias, line, wc)
    local setting = wc.setting:lower() == "on" and true or false
    Events.gag_all(setting)
    local msg = setting and "Gagging all messages." or "Not gagging anything."
    Util.msg(msg)
end


function Command.sub_event(alias, line, wc)
    local group = wc.group:lower()
    local index = tonumber(wc.index)
    local sub = wc.sub
    local value = sub:lower() ~= "none" and sub or nil
    local success = Events.sub(group, index, value)
    if not success then
        local msg = ("No event %s%d found."):format(group, index)
        Util.msg(msg)
        return
    end
    local msg
    if value == nil then
        msg = ("Removed %s%d sub."):format(group, index)
    else
        msg = ("Added sub for %s%d:\n    %s"):format(group, index, sub)
    end
    Util.msg(msg)
end


--------------------------------------------------------------------------------
-- Util
--------------------------------------------------------------------------------
Util = {}

Util.ansi = {
    misc = {
        reset = ANSI(0),
        bold = ANSI(1),
    },
    fg = {
        black = ANSI(30),
        red = ANSI(31),
        green = ANSI(32),
        yellow = ANSI(33),
        blue = ANSI(34),
        magenta = ANSI(35),
        cyan = ANSI(36),
        grey = ANSI(37),
    },
    bg = {
        black = ANSI(40),
        red = ANSI(41),
        green = ANSI(42),
        yellow = ANSI(43),
        blue = ANSI(44),
        magenta = ANSI(45),
        cyan = ANSI(46),
        grey = ANSI(47),
    },
}


function Util.print(...)
    AnsiNote(...)
end


function Util.msg(...)
    local ansi = Util.ansi
    Util.print(
        ansi.fg.grey, ansi.bg.black, "[",
        ansi.fg.yellow, ansi.misc.bold, "StarCon Soundpack",
        ansi.fg.grey, ansi.misc.reset, "] ", ...
    )
end


--------------------------------------------------------------------------------
-- Plugin Callbacks
--------------------------------------------------------------------------------
function OnPluginInstall()
    Events.initialize()
    Command.add_all()
    local msg = ("v%s loaded."):format(Const.VERSION)
    Util.msg(msg)
end


function OnPluginEnable()
    OnPluginInstall()
end


function OnPluginClose()
    Events.remove_all()
end


function OnPluginDisable()
    OnPluginClose()
end
