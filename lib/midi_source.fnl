(fn handle_midi_event [source data]
  (let [msg (midi.to_msg data)]
    (when (not= msg.type :clock)
      (print msg.type)
      (each [_ destination (ipairs source.destinations)]
        (let [callback (. source.callbacks destination)]
          (callback msg))))))

(local MIDISource {})
(set MIDISource.__index MIDISource)

(fn MIDISource.new [device]
  (let [source {: device :callbacks {} :destinations []}]
    (set device.event (partial handle_midi_event source))
    (setmetatable source MIDISource)))

(fn update_destinations [source]
  (let [destinations (icollect [k _ (pairs source.callbacks)] k)]
    (table.sort destinations)
    (set source.destinations destinations)))

(fn MIDISource.add_destination [source destination callback]
  (tset source.callbacks destination callback)
  (update_destinations source))

(fn MIDISource.remove_destination [source destination]
  (tset source.callbacks destination nil)
  (update_destinations source))

(var midi_sources {})
(var midi_source_names [])

(fn init []
  (midi.cleanup)
  (set midi_sources {})
  (set midi_source_names [])
  (for [i 1 (length midi.vports)]
    (let [device (midi.connect i)
          device_name device.name
          source (MIDISource.new device)]
      (table.insert midi_sources source)
      (table.insert midi_source_names device_name))))

(fn get_source [index]
  (. midi_sources index))

(fn get_source_action [destination callback]
  (var prev_source nil)
  (fn [index]
    (when prev_source
      (prev_source:remove_destination destination))
    (let [source (get_source index)]
      (set prev_source source)
      (source:add_destination destination callback))))

(fn get_destination_param_id [destination_id]
  (.. :trinkets_ destination_id :_midi_in_device))

(fn get_destination_param_name [destination_name]
  (.. destination_name " midi in"))

(fn add_destination [options]
  (let [{: id : name : callback} options
        param_id (get_destination_param_id id)
        param_name (get_destination_param_name name)]
    (params:add {:type :option
                 :id param_id
                 :name param_name
                 :options midi_source_names
                 :default 1
                 :action (get_source_action id callback)})))

{: init : add_destination}
