(local volt (includefnl :lib/volt))
(local Voice (require :voice))

(fn get_jf [state method]
  (. crow.ii.jf state.address method))

(fn play_voice [state channel pitch velocity]
  ((get_jf state :play_voice) channel pitch velocity))

(fn all_notes_off [state]
  (play_voice state 0 0 0)
  (set state.voice (Voice.new state.polyphony)))

(local MIDI_CHANNEL_SUFFIX :midi_channel)
(local MODE_SUFFIX :mode)
(local RUN_MODE_SUFFIX :run_mode)
(local RUN_SUFFIX :run)
(local PITCHBEND_RANGE_SUFFIX :pitchbend_range)

(local JustFriendsMode {})
(set JustFriendsMode.__index JustFriendsMode)

(fn JustFriendsMode.new []
  (setmetatable {:params [] :midi {}} JustFriendsMode))

(fn JustFriendsMode.init [state]
  (all_notes_off state))

(fn JustFriendsMode.update [_state] nil)

(fn JustFriendsMode.cleanup [state]
  (all_notes_off state))

(local JustFriendsNoop (JustFriendsMode.new))

(local JustFriendsSynth (JustFriendsMode.new))

(fn JustFriendsSynth.init [state]
  (JustFriendsMode.init state)
  ((get_jf state :mode) 1))

(fn JustFriendsSynth.cleanup [state]
  (JustFriendsMode.cleanup state)
  ((get_jf state :mode) 0))

(fn JustFriendsSynth.midi.note_on [state msg]
  (let [note msg.note
        slot (state.voice:get)
        v8 (- (volt.n2v note) 5)
        vel (volt.cc2v msg.vel)]
    (state.voice:push note slot)
    (play_voice state slot.id v8 vel)))

(fn JustFriendsSynth.midi.note_off [state msg]
  (let [note msg.note
        slot (state.voice:pop note)
        v8 (- (volt.n2v note) 5)]
    (when slot
      (state.voice:release slot)
      (play_voice state slot.id v8 0))))

(fn JustFriendsSynth.midi.pitchbend [_state msg]
  nil)

(local OFF_MODE_NAME :OFF)
(local SYNTH_MODE_NAME :SYNTH)

(local MODES {OFF_MODE_NAME JustFriendsNoop SYNTH_MODE_NAME JustFriendsSynth})

(local MODE_OPTIONS [OFF_MODE_NAME SYNTH_MODE_NAME])

(fn get_mode [mode_index]
  "Look up the mode and mode name at the given index"
  (let [mode_name (. MODE_OPTIONS mode_index)
        mode (. MODES mode_name)]
    (values mode mode_name)))

(fn init_just_friends_state [address]
  (let [mode_index 1
        (mode mode_name) (get_mode mode_index)
        polyphony 6]
    {: address
     :mode_index 1
     : mode_name
     : mode
     :midi_channel 1
     : polyphony
     :unison 1
     :voice (Voice.new polyphony)
     :pitchbend {}}))

(fn get_just_friends_param_id [state suffix]
  (.. :trinkets_jf state.address "_" suffix))

(fn set_just_friends_midi_channel [state value]
  (set state.midi_channel value))

(fn add_just_friends_midi_channel_param [state]
  (params:add {:type :number
               :id (get_just_friends_param_id state MIDI_CHANNEL_SUFFIX)
               :name "midi channel"
               :min 1
               :max 16
               :default state.midi_channel
               :action (partial set_just_friends_midi_channel state)}))

(fn set_just_friends_mode [state value]
  (when state.mode
    (state.mode.cleanup state))
  (let [(mode mode_name) (get_mode value)]
    (set state.mode_index value)
    (set state.mode_name mode_name)
    (set state.mode mode))
  (state.mode.init state)
  (_menu.rebuild_params))

(fn add_just_friends_mode_param [state]
  (params:add {:type :option
               :id (get_just_friends_param_id state MODE_SUFFIX)
               :name :mode
               :options MODE_OPTIONS
               :default state.mode_index
               :action (partial set_just_friends_mode state)}))

(local JUST_FRIENDS_PARAM_GROUP
       [add_just_friends_midi_channel_param add_just_friends_mode_param])

(fn update_state [state msg]
  (when (= msg.ch state.midi_channel)
    (if (and (= msg.type :cc) (= msg.cc 120))
        (state.mode.init state)
        (let [mode_callback (. state.mode.midi msg.type)]
          (when mode_callback
            (mode_callback state msg))))))

(fn add_just_friends [address sources]
  (let [state (init_just_friends_state address)
        group_id (get_just_friends_param_id state :group)
        group_name (.. "JUST FRIENDS " address)
        group_size (+ 1 (length JUST_FRIENDS_PARAM_GROUP))]
    (params:add_group group_id group_name group_size)
    (sources.add_destination {:id (.. :jf address)
                              :name (.. "jf " address)
                              :callback (partial update_state state)})
    (each [_ add_param (ipairs JUST_FRIENDS_PARAM_GROUP)]
      (add_param state))
    state))

(var states nil)

(fn init [sources]
  (let [s (fcollect [i 1 2]
            (add_just_friends i sources))]
    (set states s))
  states)

(fn cleanup []
  (each [_ state (ipairs states)]
    (state.mode.cleanup state)))

{: init : cleanup}
