(fn n2v [n]
  "Convert a MIDI note to a control voltage"
  (/ n 12))

(fn cc2v [cc]
  "Convert a MIDI CC value to a control voltage"
  (/ cc 127))

(fn set_crow_out_volts [state volts]
  (tset crow.output state.output_index :volts volts)
  state)

(fn reset_crow_out_volts [state]
  (set_crow_out_volts state 0)
  state)

(fn set_crow_out_note [state note]
  (set state.note note)
  state)

(fn set_crow_out_pitchbend [state value]
  (let [pitchbend_range_v (/ state.pitchbend_range 12)
        pitchbend_normalized (/ (- value 8192) 8192)
        pitchbend_v (* pitchbend_range_v pitchbend_normalized)]
    (set state.pitchbend pitchbend_v))
  state)

(fn update_crow_out_voct [state]
  (let [volts (+ state.volt_offset (n2v state.note) state.pitchbend)]
    (set_crow_out_volts state volts))
  state)

(local CrowOutMode {})
(set CrowOutMode.__index CrowOutMode)
(fn CrowOutMode.new [params]
  (setmetatable {:params (or params []) :midi {}} CrowOutMode))

(fn CrowOutMode.init [_state])
(fn CrowOutMode.update [_state])
(fn CrowOutMode.cleanup [state]
  (reset_crow_out_volts state))

(local MIDI_CHANNEL_SUFFIX :midi_channel)
(local SLEW_RATE_SUFFIX :slew_rate)
(local MODE_SUFFIX :mode)
(local PITCHBEND_RANGE_SUFFIX :pitchbend_range)
(local VOLT_OFFSET_SUFFIX :volt_offset)
(local VOLT_RANGE_SUFFIX :volt_range)
(local CONTROL_SUFFIX :control)
(local PULSE_DURATION_SUFFIX :pulse_duration)
(local CLOCK_DIVISION_SUFFIX :clock_division)

(local CROW_OUT_MODE_PARAMS [PITCHBEND_RANGE_SUFFIX
                             VOLT_OFFSET_SUFFIX
                             VOLT_RANGE_SUFFIX
                             CONTROL_SUFFIX
                             PULSE_DURATION_SUFFIX
                             CLOCK_DIVISION_SUFFIX])

(local CrowOutNote
       (CrowOutMode.new [PITCHBEND_RANGE_SUFFIX VOLT_OFFSET_SUFFIX]))

(fn CrowOutNote.cleanup [state]
  (set state.note nil)
  (set state.pitchbend 0)
  (CrowOutMode.cleanup state))

(fn CrowOutNote.midi.note_on [state msg]
  (-> state
      (set_crow_out_note msg.note)
      (update_crow_out_voct)))

(fn CrowOutNote.midi.pitchbend [state msg]
  (when state.note
    (-> state
        (set_crow_out_pitchbend msg.val)
        (update_crow_out_voct))))

(local CrowOutGate (CrowOutMode.new [VOLT_RANGE_SUFFIX]))

(fn CrowOutGate.cleanup [state]
  (set state.note nil)
  (CrowOutMode.cleanup state))

(fn CrowOutGate.midi.note_on [state msg]
  (-> state
      (set_crow_out_note msg.note)
      (set_crow_out_volts state.volt_range)))

(fn CrowOutGate.midi.note_off [state msg]
  (when (= msg.note state.note)
    (reset_crow_out_volts state)))

(local CrowOutTrig (CrowOutMode.new [VOLT_RANGE_SUFFIX PULSE_DURATION_SUFFIX]))

(fn CrowOutTrig.midi.note_on [state _msg]
  (let [action (.. "{to(" state.volt_range ",0),to(0," state.pulse_duration
                   ")}")
        output (. crow.output state.output_index)]
    (set output.action action)
    (output)))

(local CrowOutVelocity (CrowOutMode.new [VOLT_RANGE_SUFFIX]))

(fn CrowOutVelocity.cleanup [state]
  (set state.note nil)
  (CrowOutMode.cleanup state))

(fn CrowOutVelocity.midi.note_on [state msg]
  (let [volts (* state.volt_range (cc2v msg.vel))]
    (-> state
        (set_crow_out_note msg.note)
        (set_crow_out_volts volts))))

(fn CrowOutVelocity.midi.note_off [state msg]
  (when (= msg.note state.note)
    (reset_crow_out_volts state)))

(local CrowOutControl (CrowOutMode.new [VOLT_OFFSET_SUFFIX
                                        VOLT_RANGE_SUFFIX
                                        CONTROL_SUFFIX]))

(local CrowOutClock (CrowOutMode.new [VOLT_RANGE_SUFFIX CLOCK_DIVISION_SUFFIX]))

(fn run_crow_out_clock [state]
  (while true
    (clock.sync (/ 1 state.clock_division))
    (set_crow_out_volts state state.volt_range)
    (clock.sleep (/ 60 (* 2 (clock.get_tempo) state.clock_division)))
    (reset_crow_out_volts state)))

(fn CrowOutClock.init [state]
  (let [coro (->> state
                  (partial run_crow_out_clock)
                  (clock.run))]
    (set state.clock coro)))

(fn CrowOutClock.cleanup [state]
  (when state.clock
    (clock.cancel state.clock)
    (set state.clock nil)
    (CrowOutMode.cleanup state)))

(local NOTE_MODE_NAME :NOTE)
(local GATE_MODE_NAME :GATE)
(local TRIG_MODE_NAME :TRIG)
(local VELOCITY_MODE_NAME :VELOCITY)
(local CONTROL_MODE_NAME :CONTROL)
(local CLOCK_MODE_NAME :CLOCK)

(local MODES {NOTE_MODE_NAME CrowOutNote
              GATE_MODE_NAME CrowOutGate
              TRIG_MODE_NAME CrowOutTrig
              VELOCITY_MODE_NAME CrowOutVelocity
              CONTROL_MODE_NAME CrowOutControl
              CLOCK_MODE_NAME CrowOutClock})

(fn find_index [list elem]
  (accumulate [index nil i val (ipairs list) &until (not= index nil)]
    (when (= val elem) i)))

(local MODE_OPTIONS [NOTE_MODE_NAME
                     GATE_MODE_NAME
                     TRIG_MODE_NAME
                     VELOCITY_MODE_NAME
                     CONTROL_MODE_NAME
                     CLOCK_MODE_NAME])

(local NOTE_MODE (find_index MODE_OPTIONS NOTE_MODE_NAME))
(local GATE_MODE (find_index MODE_OPTIONS GATE_MODE_NAME))
(local VELOCITY_MODE (find_index MODE_OPTIONS VELOCITY_MODE_NAME))
(local CONTROL_MODE (find_index MODE_OPTIONS CONTROL_MODE_NAME))

(fn get_mode_name [mode_index]
  (. MODE_OPTIONS mode_index))

(fn get_mode [mode_name]
  (. MODES mode_name))

(fn get_crow_out_param_id [output_index param_suffix]
  (.. :trinkets_crow_out output_index "_" param_suffix))

(fn set_crow_out_midi_channel [state value]
  (set state.midi_channel value))

(fn set_crow_out_slew_rate [state value]
  (set state.slew_rate value)
  (tset crow.output state.output_index :slew value))

(fn set_crow_out_mode [state value]
  (when state.mode
    (state.mode.cleanup state)
    (each [_ suffix (ipairs state.mode.params)]
      (params:hide (get_crow_out_param_id state.output_index suffix))))
  (set state.mode_index value)
  (set state.mode_name (get_mode_name value))
  (set state.mode (get_mode state.mode_name))
  (state.mode.init state)
  (each [_ suffix (ipairs CROW_OUT_MODE_PARAMS)]
    (params:show (get_crow_out_param_id state.output_index suffix)))
  (_menu.rebuild_params))

(fn set_crow_out_pitchbend_range [state value]
  (set state.pitchbend_range value))

(fn set_crow_out_volt_offset [state value]
  (set state.volt_offset value)
  (state.mode.update state))

(fn set_crow_out_volt_range [state value]
  (set state.volt_range value)
  (state.mode.update state))

(fn set_crow_out_control [state value]
  (when (= state.mode_name :CONTROL)
    (let [volts (+ state.volt_offset (* state.volt_range (cc2v value)))]
      (set_crow_out_volts state volts))))

(fn set_crow_out_pulse_duration [state value]
  (set state.pulse_duration value)
  (state.mode.update state))

(fn set_crow_out_clock_division [state value]
  (set state.clock_division value))

(fn init_crow_out_state [output_index mode_index]
  (let [mode_name (get_mode_name mode_index)
        mode (get_mode mode_name)]
    {: output_index
     : mode_index
     : mode_name
     : mode
     :midi_channel 1
     :slew_rate 0
     :pitchbend_range 2
     :volt_offset 0
     :volt_range 10
     :pulse_duration 0.005
     :clock_division 1
     :note nil
     :pitchbend 0}))

(fn add_crow_out_midi_channel_param [state]
  (params:add {:type :number
               :id (get_crow_out_param_id state.output_index
                                          MIDI_CHANNEL_SUFFIX)
               :name "midi channel"
               :min 1
               :max 16
               :default state.midi_channel
               :action (partial set_crow_out_midi_channel state)}))

(fn add_crow_out_slew_rate_param [state]
  (params:add {:type :control
               :id (get_crow_out_param_id state.output_index SLEW_RATE_SUFFIX)
               :name "slew rate"
               :controlspec (controlspec.def {:min 0
                                              :max 1
                                              :warp :lin
                                              :step 0
                                              :default state.slew_rate})
               :action (partial set_crow_out_slew_rate state)}))

(fn add_crow_out_mode_param [state]
  (params:add {:type :option
               :id (get_crow_out_param_id state.output_index MODE_SUFFIX)
               :name :mode
               :options MODE_OPTIONS
               :default state.mode_index
               :action (partial set_crow_out_mode state)}))

(fn add_crow_out_pitchbend_param [state]
  (params:add {:type :number
               :id (get_crow_out_param_id state.output_index
                                          PITCHBEND_RANGE_SUFFIX)
               :name "pitchbend range"
               :min 0
               :max 48
               :default state.pitchbend_range
               :action (partial set_crow_out_pitchbend_range state)}))

(fn add_crow_out_volt_offset_param [state]
  (params:add {:type :number
               :id (get_crow_out_param_id state.output_index VOLT_OFFSET_SUFFIX)
               :name "volt offset"
               :min -5
               :max 0
               :default state.volt_offset
               :action (partial set_crow_out_volt_offset state)}))

(fn add_crow_out_volt_range_param [state]
  (params:add {:type :number
               :id (get_crow_out_param_id state.output_index VOLT_RANGE_SUFFIX)
               :name "volt range"
               :min 0
               :max 10
               :default state.volt_range
               :action (partial set_crow_out_volt_range state)}))

(fn add_crow_out_control_param [state]
  (params:add {:type :number
               :id (get_crow_out_param_id state.output_index CONTROL_SUFFIX)
               :name :control
               :min 0
               :max 127
               :default 0
               :action (partial set_crow_out_control state)}))

(fn add_crow_out_pulse_duration_param [state]
  (params:add {:type :control
               :id (get_crow_out_param_id state.output_index
                                          PULSE_DURATION_SUFFIX)
               :name "pulse duration"
               :controlspec (controlspec.def {:min 0.001
                                              :max 0.1
                                              :warp :lin
                                              :step 0.001
                                              :default state.pulse_duration
                                              :units ""
                                              :wrap false})
               :formatter (fn [param] (param:get))
               :action (partial set_crow_out_pulse_duration state)}))

(fn add_crow_out_clock_division_param [state]
  (params:add {:type :number
               :id (get_crow_out_param_id state.output_index
                                          CLOCK_DIVISION_SUFFIX)
               :name "clock division"
               :min 1
               :max 32
               :default state.clock_division
               :action (partial set_crow_out_clock_division state)}))

(local CROW_OUT_PARAM_GROUP
       [add_crow_out_midi_channel_param
        add_crow_out_slew_rate_param
        add_crow_out_mode_param
        add_crow_out_pitchbend_param
        add_crow_out_volt_offset_param
        add_crow_out_volt_range_param
        add_crow_out_control_param
        add_crow_out_pulse_duration_param
        add_crow_out_clock_division_param])

(fn add_crow_out [output_index mode_index]
  (let [state (init_crow_out_state output_index mode_index)]
    (params:add_group (get_crow_out_param_id output_index :group)
                      (.. "OUTPUT " output_index) (length CROW_OUT_PARAM_GROUP))
    (each [_ add_param (ipairs CROW_OUT_PARAM_GROUP)]
      (add_param state))
    state))

(local DEFAULT_CROW_OUT_MODES [NOTE_MODE GATE_MODE VELOCITY_MODE CONTROL_MODE])

(fn init []
  (let [crow_out_states (icollect [output_index mode_index (ipairs DEFAULT_CROW_OUT_MODES)]
                          (add_crow_out output_index mode_index))]
    (set _G.crow_out_states crow_out_states)))

(fn update [state msg]
  (when (= msg.ch state.midi_channel)
    (if (and (= msg.type :cc) (= msg.cc 120))
        (state.mode.cleanup state)
        (let [mode_callback (. state.mode.midi msg.type)]
          (when mode_callback
            (mode_callback state msg))))))

{: init : update}

