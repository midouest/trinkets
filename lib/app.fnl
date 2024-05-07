(local midi_src (includefnl :lib/midi_source))
(local crow_out (includefnl :lib/crow_out))
(local just_friends (includefnl :lib/just_friends))

(var should_redraw true)
(fn request_redraw []
  (set should_redraw true))

(fn run_redraw_clock []
  (while true
    (_G.redraw)
    (clock.sleep (/ 1 15))))

(fn start_redraw []
  (clock.run run_redraw_clock))

(fn init []
  (params:add_separator :trinkets_separator :TRINKETS)
  (midi_src.init)
  (crow_out.init midi_src)
  (just_friends.init midi_src)
  (params:default)
  (start_redraw))

(fn cleanup []
  (crow_out.cleanup))

(fn redraw []
  (when should_redraw
    (set should_redraw false)
    (screen.clear)
    (screen.update)))

(fn enc [_n _d])

(fn key [_n _z])

{: init : cleanup : redraw : enc : key}
