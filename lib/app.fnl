(local crow_out (includefnl :lib/crow_out))

(var should_redraw true)
(fn request_redraw []
  (set should_redraw true))

(fn run_redraw_clock []
  (while true
    (_G.redraw)
    (clock.sleep (/ 1 15))))

(var redraw_clock nil)
(fn start_redraw []
  (set redraw_clock (clock.run run_redraw_clock)))

(fn stop_redraw []
  (clock.cancel redraw_clock))

(fn midi_event [data]
  (let [msg (midi.to_msg data)]
    (when (not= msg.type :clock)
      (crow_out.update msg))))

(fn get_midi_devices []
  (fcollect [i 1 (length midi.vports)]
    (. midi.vports i :name)))

(fn set_midi_device [index]
  (midi.cleanup)
  (let [device (midi.connect index)]
    (set device.event midi_event)))

(fn init []
  (params:add_separator :trinkets_separator :TRINKETS)
  (params:add {:type :option
               :id :trinkets_midi_in_device
               :name "midi in"
               :options (get_midi_devices)
               :default 1
               :action set_midi_device})
  (crow_out.init)
  (params:default)
  (start_redraw))

(fn cleanup []
  (stop_redraw))

(fn redraw []
  (when should_redraw
    (set should_redraw false)
    (screen.clear)
    (screen.update)))

(fn enc [_n _d])

(fn key [_n _z])

{: init : cleanup : redraw : enc : key}

