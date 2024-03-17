--------------------------------------------------------------------------------
-- Dependencies
--------------------------------------------------------------------------------
require "json"
require "var"
require "wait"

CMD_PREFIX = "sp"


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
    local events = json.decode(var.events or Config.get_events_default())
    table.sort(events, sort)
    return events
end


function Config.set_events(value)
    var.events = json.encode(value)
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


function Events.add_one(trigger)
    local flags = trigger_flag.Enabled + trigger_flag.KeepEvaluating
        + trigger_flag.Replace + trigger_flag.Temporary
    if trigger.regex then
        flags = flags + trigger_flag.RegularExpression
    end
    if trigger.gag then
        flags = flags + trigger_flag.OmitFromOutput
    end

    -- Construct the response script dynamically from sounds list (if any).
    -- Allow for numberic entries, which indicate a pause between sounds.
    local response_lines = {}
    table.insert(response_lines, "wait.make(function()")
    for _, sound in ipairs(trigger.sounds or {}) do
        local line = "    Sound.play(\"%s\")"
        local pause = tonumber(sound)
        if pause ~= nil then
            line = "    wait.time(%d)"
            line = line:format(pause)
        else
            line = line:format(sound)
        end
        table.insert(response_lines, line)
    end
    table.insert(response_lines, "end)")
    if trigger.script ~= nil then
        table.insert(response_lines, trigger.script)
    end
    response = table.concat(response_lines, "\n")

    -- Dynamically assign a trigger name.
				local trigger_list = GetTriggerList() or {}
    local trigger_count = #trigger_list
    local name = ("trigger_sound%d"):format(trigger_count)

    local code = AddTriggerEx(
        name, trigger.match,
        response, flags, custom_colour.NoChange,
        0, "", "", sendto.script, 100
    )
    if code ~= error_code.eOK then
        local err = error_desc[code]
        local msg = ("Failed to add trigger %s: %s."):format(name, err)
        Util.msg(msg)
        return false
    end
    return true
end


function Events.add_all()
    local trigger_data = Config.get_events()
    for i, trigger in ipairs(trigger_data) do
        Events.add_one(trigger)
    end
end


function Events.get_groups(events)
    local groups = {}
    local groups_found = {}
    for i, event in ipairs(events) do
        local group = event.group
        if groups_found[group] == nil then
            groups_found[group] = true
            table.insert(groups, group)
        end
    end
    table.sort(groups)
    return groups
end


function Events.get_in_group(events, group)
    local in_group = {}
    for i, event in ipairs(events) do
        if event.group == group then
            table.insert(in_group, event)
        end
    end
    return in_group
end


--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
Command = {}

Command.list = {
    {
        name = "list_groups",
        match = "^ *" .. CMD_PREFIX .. " +li?st? *$",
        script = "Command.list_groups",
    },
    {
        name = "list_events",
        match = "^ *" .. CMD_PREFIX .. " +li?st? +(?<group>\\w+) *$",
        script = "Command.list_events",
    },
    {
        name = "config_volume",
        match = "^ *" .. CMD_PREFIX .. " +vol(?:ume)? +(?<value>\\d+) *$",
        script = "Command.set_volume",
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
    return true
end


function Command.add_all()
    for i, command in ipairs(Command.list) do
        Command.add_one(command)
    end
end


function Command.list_groups(alias, line, wc)
    local events = Config.get_events()
    local groups = Events.get_groups(events)
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
    local events = Config.get_events()
    local in_group = Events.get_in_group(events, group)
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
    Events.add_all()
    Command.add_all()
    Util.msg("Loaded.")
end


function OnPluginEnable()
    OnPluginInstall()
end
