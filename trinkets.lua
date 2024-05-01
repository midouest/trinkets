-- flexible midi-to-crow routing
tabutil = require "tabutil"

function n2v(n) return n / 12 end

function cc2v(cc) return cc / 127 end

function set_trinket_note(trinket, note) trinket.note = note end

function set_trinket_pitchbend(trinket, pitchbend)
    trinket.pitchbend = (trinket.pitchbend_range / 12) * (pitchbend - 8192) /
                            8192
end

function update_trinket_voct(trinket)
    crow.output[trinket.output].volts =
        trinket.volt_offset + n2v(trinket.note) + trinket.pitchbend
end

function all_notes_off(trinket)
    trinket.note = nil
    trinket.pitchbend = 0
    crow.output[trinket.output].volts = 0
end

CHANNEL_SUFFIX = "channel"
SLEW_RATE_SUFFIX = "slew_rate"
MODE_SUFFIX = "mode"
PITCHBEND_RANGE_SUFFIX = "pitchbend_range"
VOLT_OFFSET_SUFFIX = "volt_offset"
VOLT_RANGE_SUFFIX = "volt_range"
CONTROL_SUFFIX = "control"
PULSE_DURATION_SUFFIX = "pulse_duration"
CLOCK_DIVISION_SUFFIX = "clock_division"

COMMON_TRINKET_PARAMS = {CHANNEL_SUFFIX, SLEW_RATE_SUFFIX, MODE_SUFFIX}

TRINKET_PARAMS = {
    PITCHBEND_RANGE_SUFFIX, VOLT_OFFSET_SUFFIX, VOLT_RANGE_SUFFIX,
    CONTROL_SUFFIX, PULSE_DURATION_SUFFIX, CLOCK_DIVISION_SUFFIX
}

NoteMode = {params = {PITCHBEND_RANGE_SUFFIX, VOLT_OFFSET_SUFFIX}, event = {}}

function NoteMode.init(trinket) end

function NoteMode.update(trinket) end

function NoteMode.cleanup(trinket) crow.output[trinket.output].volts = 0 end

function NoteMode.event.note_on(trinket, msg)
    set_trinket_note(trinket, msg.note)
    update_trinket_voct(trinket)
end

function NoteMode.event.pitchbend(trinket, msg)
    if trinket.note == nil then return end
    set_trinket_pitchbend(trinket, msg.val)
    update_trinket_voct(trinket)
end

GateMode = {params = {VOLT_RANGE_SUFFIX}, event = {}}

function GateMode.init(trinket) end

function GateMode.update(trinket) end

function GateMode.cleanup(trinket) crow.output[trinket.output].volts = 0 end

function GateMode.event.note_on(trinket, msg)
    set_trinket_note(trinket, msg.note)
    crow.output[trinket.output].volts = trinket.volt_range
end

function GateMode.event.note_off(trinket, msg)
    if msg.note ~= trinket.note then return end
    crow.output[trinket.output].volts = 0
end

TrigMode = {params = {VOLT_RANGE_SUFFIX, PULSE_DURATION_SUFFIX}, event = {}}

function TrigMode.init(trinket) end

function TrigMode.update(trinket) end

function TrigMode.cleanup(trinket) crow.output[trinket.output].volts = 0 end

function TrigMode.event.note_on(trinket, msg)
    local action = "{to(" .. tostring(trinket.volt_range) .. ",0),to(0," ..
                       tostring(trinket.pulse_duration) .. ")}"
    crow.output[trinket.output].action = action
    crow.output[trinket.output]()
end

VelocityMode = {params = {VOLT_RANGE_SUFFIX}, event = {}}

function VelocityMode.init(trinket) end

function VelocityMode.update(trinket) end

function VelocityMode.cleanup(trinket) crow.output[trinket.output].volts = 0 end

function VelocityMode.event.note_on(trinket, msg)
    set_trinket_note(trinket, msg.note)
    crow.output[trinket.output].volts = trinket.volt_range * cc2v(msg.vel)
end

function VelocityMode.event.note_off(trinket, msg)
    if msg.note ~= trinket.note then return end
    crow.output[trinket.output].volts = 0
end

ControlMode = {
    params = {VOLT_OFFSET_SUFFIX, VOLT_RANGE_SUFFIX, CONTROL_SUFFIX},
    event = {}
}

function ControlMode.init(trinket) end

function ControlMode.update(trinket) end

function ControlMode.cleanup(trinket) end

ClockMode = {params = {VOLT_RANGE_SUFFIX, CLOCK_DIVISION_SUFFIX}, event = {}}

function ClockMode.init(trinket)
    trinket.clock = clock.run(function()
        while true do
            clock.sync(1 / trinket.clock_division)
            crow.output[trinket.output].volts = trinket.volt_range
            clock.sleep(60 / (2 * clock.get_tempo() * trinket.clock_division))
            crow.output[trinket.output].volts = 0
        end
    end)
end

function ClockMode.update(trinket) end

function ClockMode.cleanup(trinket)
    if trinket.clock == nil then return end
    clock.cancel(trinket.clock)
    trinket.clock = nil
end

function update_trinket(trinket, msg)
    if msg.ch ~= trinket.channel then return end

    if msg.type == "cc" and msg.cc == 120 then
        all_notes_off(trinket)
        return
    end

    local mode_callback = trinket.mode.event[msg.type]
    if mode_callback == nil then return end

    mode_callback(trinket, msg)
end

function midi_event(data)
    local msg = midi.to_msg(data)
    if msg.type == "clock" then return end
    for _, trinket in ipairs(trinkets) do update_trinket(trinket, msg) end
end

MODES = {
    {name = "NOTE", mode = NoteMode}, {name = "GATE", mode = GateMode},
    {name = "TRIG", mode = TrigMode}, {name = "VELOCITY", mode = VelocityMode},
    {name = "CONTROL", mode = ControlMode}, {name = "CLOCK", mode = ClockMode}
}

NOTE_INDEX = 1
GATE_INDEX = 2
TRIG_INDEX = 3
VELOCITY_INDEX = 4
CONTROL_INDEX = 5
CLOCK_INDEX = 6

MODE_OPTIONS = {}
for _, mode in ipairs(MODES) do table.insert(MODE_OPTIONS, mode.name) end

function add_trinket(output, mode_index)
    local trinket = {
        output = output,
        note = nil,
        pitchbend = 0,
        channel = 1,
        slew_rate = 0,
        mode_index = mode_index,
        mode_name = MODES[mode_index].name,
        mode = MODES[mode_index].mode,
        pitchbend_range = 2,
        volt_offset = 0,
        volt_range = 10,
        pulse_duration = 0.005,
        clock_division = 1
    }

    params:add_group("trinket_out" .. output .. "_group", "OUTPUT " .. output,
                     #COMMON_TRINKET_PARAMS + #TRINKET_PARAMS)

    params:add{
        type = "number",
        id = "trinket_out" .. output .. "_channel",
        name = "midi channel",
        min = 1,
        max = 16,
        default = trinket.channel,
        action = function(value) trinket.channel = value end
    }

    params:add{
        type = "control",
        id = "trinket_out" .. output .. "_slew",
        name = "slew rate",
        controlspec = controlspec.def {
            min = 0,
            max = 1,
            warp = "lin",
            step = 0,
            default = trinket.slew_rate
        },
        action = function(value)
            trinket.slew_rate = value
            crow.output[output].slew = value
        end
    }

    params:add{
        type = "option",
        id = "trinket_out" .. output .. "_mode",
        name = "mode",
        options = MODE_OPTIONS,
        default = trinket.mode_index,
        action = function(value)
            if trinket.mode ~= nil then
                trinket.mode.cleanup(trinket)
                for _, suffix in ipairs(trinket.mode.params) do
                    params:hide("trinket_out" .. output .. "_" .. suffix)
                end
            end

            trinket.mode_index = value
            trinket.mode_name = MODES[value].name
            trinket.mode = MODES[value].mode
            trinket.mode.init(trinket)
            for _, suffix in ipairs(trinket.mode.params) do
                params:show("trinket_out" .. output .. "_" .. suffix)
            end
            _menu.rebuild_params()
        end
    }

    params:add{
        type = "number",
        id = "trinket_out" .. output .. "_pitchbend_range",
        name = "pitchbend range",
        min = 0,
        max = 48,
        default = trinket.pitchbend_range,
        action = function(value) trinket.pitchbend_range = value end
    }

    params:add{
        type = "number",
        id = "trinket_out" .. output .. "_volt_offset",
        name = "volt offset",
        min = -5,
        max = 0,
        default = trinket.volt_offset,
        action = function(value)
            trinket.volt_offset = value
            if trinket.mode ~= nil then trinket.mode.update(trinket) end
        end
    }

    params:add{
        type = "number",
        id = "trinket_out" .. output .. "_volt_range",
        name = "volt range",
        min = 0,
        max = 10,
        default = trinket.volt_range,
        action = function(value)
            trinket.volt_range = value
            if trinket.mode ~= nil then trinket.mode.update(trinket) end
        end
    }

    params:add{
        type = "number",
        id = "trinket_out" .. output .. "_control",
        name = "control",
        min = 0,
        max = 127,
        default = 0,
        action = function(value)
            if trinket.mode_index ~= CONTROL_INDEX then return end
            crow.output[trinket.output].volts =
                trinket.volt_offset + trinket.volt_range * cc2v(value)
        end
    }

    params:add{
        type = "control",
        id = "trinket_out" .. output .. "_pulse_duration",
        name = "pulse duration",
        controlspec = controlspec.def {
            min = 0.001,
            max = 0.1,
            warp = "lin",
            step = 0.001,
            default = trinket.pulse_duration,
            units = "",
            wrap = false
        },
        formatter = function(param) return param:get() end,
        action = function(value)
            trinket.pulse_duration = value
            if trinket.mode ~= nil then trinket.mode.update(trinket) end
        end
    }

    params:add{
        type = "number",
        id = "trinket_out" .. output .. "_clock_division",
        name = "clock division",
        min = 1,
        max = 32,
        default = trinket.clock_division,
        action = function(value) trinket.clock_division = value end
    }

    for _, suffix in ipairs(TRINKET_PARAMS) do
        params:hide("trinket_out" .. output .. "_" .. suffix)
    end

    return trinket
end

function get_midi_devices()
    local devices = {}
    for i = 1, #midi.vports do
        local long_name = midi.vports[i].name
        table.insert(devices, long_name)
    end
    return devices
end

function init()
    midi_devices = get_midi_devices()
    trinkets = {}

    params:hide("CLOCK")
    params:add_separator("trinket_separator", "TRINKETS")

    params:add{
        type = "option",
        id = "trinket_midi_in_device",
        name = "midi in",
        options = midi_devices,
        default = 1,
        action = function(value)
            midi.cleanup()
            midi_device = midi.connect(value)
            midi_device.event = midi_event
            params:set("clock_source", 2)
            params:set("clock_midi_in", value + 2)
        end
    }
    params:set_save("trinket_midi_in_device", false)

    local default_modes = {
        NOTE_INDEX, GATE_INDEX, VELOCITY_INDEX, CONTROL_INDEX
    }
    for i, mode in ipairs(default_modes) do
        local trinket = add_trinket(i, mode)
        table.insert(trinkets, trinket)
    end

    params:default()
end

function key(n, z) end

function enc(n, d) end

function redraw() end
