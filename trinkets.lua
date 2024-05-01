-- flexible midi-to-crow routing
function n2v(n) return n / 12 end

function cc2v(cc) return cc / 127 end

common_mode = {}

function common_mode.note_on(trinket, msg) trinket.note = msg.note end

function common_mode.pitchbend(trinket, msg)
    trinket.pitchbend = (trinket.pitchbend_range / 12) * (msg.val - 8192) / 8192
end

note_mode = {}

function note_mode.note_on(trinket, msg)
    crow.output[trinket.output].volts =
        trinket.volt_offset + n2v(trinket.note) + trinket.pitchbend
end

function note_mode.pitchbend(trinket, msg)
    if trinket.note == nil then return end
    crow.output[trinket.output].volts =
        trinket.volt_offset + n2v(trinket.note) + trinket.pitchbend
end

gate_mode = {}

function gate_mode.note_on(trinket, msg)
    crow.output[trinket.output].volts = trinket.volt_offset + trinket.volt_range
end

function gate_mode.note_off(trinket, msg)
    if msg.note ~= trinket.note then return end
    crow.output[trinket.output].volts = trinket.volt_offset
end

velocity_mode = {}

function velocity_mode.note_on(trinket, msg)
    crow.output[trinket.output].volts =
        trinket.volt_offset + trinket.volt_range * cc2v(msg.vel)
end

function velocity_mode.note_off(trinket, msg)
    if msg.note ~= trinket.note then return end
    crow.output[trinket.output].volts = trinket.volt_offset
end

noop_mode = {}

modes = {
    {name = "NOTE", mode = note_mode}, {name = "GATE", mode = gate_mode},
    {name = "VELOCITY", mode = velocity_mode},
    {name = "CONTROL", mode = noop_mode}
}

function update_trinket(trinket, msg)
    if msg.ch ~= trinket.channel then return end

    local common_callback = common_mode[msg.type]
    if common_callback ~= nil then common_callback(trinket, msg) end

    local mode_callback = trinket.mode[msg.type]
    if mode_callback ~= nil then mode_callback(trinket, msg) end
end

function midi_event(data)
    local msg = midi.to_msg(data)
    if msg.type == "clock" then return end
    for _, trinket in ipairs(trinkets) do update_trinket(trinket, msg) end
end

mode_options = {}
for _, mode in ipairs(modes) do table.insert(mode_options, mode.name) end

function add_trinket(output, mode)
    local trinket = {output = output}

    params:add_group("TRINKET " .. output, 7)

    params:add{
        type = "number",
        id = "trinket" .. output .. "_channel",
        name = "midi channel",
        min = 1,
        max = 16,
        default = 1,
        action = function(value) trinket.channel = value end
    }

    params:add{
        type = "control",
        id = "trinket" .. output .. "_slew",
        name = "slew rate",
        controlspec = controlspec.UNIPOLAR,
        action = function(value)
            trinket.slew_rate = value
            crow.output[output].slew = value
        end
    }

    params:add{
        type = "option",
        id = "trinket" .. output .. "_mode",
        name = "mode",
        options = mode_options,
        default = mode or 1,
        action = function(value)
            trinket.mode_index = value
            trinket.mode = modes[value].mode
        end
    }

    params:add{
        type = "number",
        id = "trinket" .. output .. "_pitchbend_range",
        name = "pitchbend range",
        min = 0,
        max = 48,
        default = 2,
        action = function(value)
            trinket.pitchbend_range = value
            trinket.pitchbend = trinket.pitchbend or 0
        end
    }

    params:add{
        type = "control",
        id = "trinket" .. output .. "_volt_offset",
        name = "volt offset",
        controlspec = controlspec.def {
            min = -5,
            max = 10,
            warp = "lin",
            step = 1,
            default = 0,
            units = "v",
            quantum = 0.01,
            wrap = false
        },
        action = function(value) trinket.volt_offset = value end
    }

    params:add{
        type = "control",
        id = "trinket" .. output .. "_volt_range",
        name = "volt range",
        controlspec = controlspec.def {
            min = -15,
            max = 15,
            warp = "lin",
            step = 1,
            default = 10,
            units = "v",
            quantum = 0.01,
            wrap = false
        },
        action = function(value) trinket.volt_range = value end
    }

    params:add{
        type = "number",
        id = "trinket" .. output .. "_control",
        name = "control",
        min = 0,
        max = 127,
        default = 0,
        action = function(value)
            crow.output[trinket.output].volts =
                trinket.volt_offset + trinket.volt_range * cc2v(value)
        end
    }

    return trinket
end

function get_midi_devices()
    local devices = {}
    for i = 1, #midi.vports do
        local long_name = midi.vports[i].name
        -- local short_name = string.len(long_name) > 15 and util.acronym(long_name) or long_name
        table.insert(devices, long_name)
    end
    return devices
end

function init()
    midi_devices = get_midi_devices()
    trinkets = {}

    params:add_separator("TRINKETS")

    params:add{
        type = "option",
        id = "midi_in_device",
        name = "midi in",
        options = midi_devices,
        default = 1,
        action = function(value)
            midi.cleanup()
            midi_device = midi.connect(value)
            midi_device.event = midi_event
        end
    }

    local trinket_modes = {1, 2, 3, 4}
    for i, mode in ipairs(trinket_modes) do
        local trinket = add_trinket(i, mode)
        table.insert(trinkets, trinket)
    end

    params:default()
end

function key(n, z) end

function enc(n, d) end

function redraw() end
