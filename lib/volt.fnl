(fn n2v [n]
  "Convert a MIDI note to a control voltage"
  (/ n 12))

(fn cc2v [cc]
  "Convert a MIDI CC value to a control voltage"
  (/ cc 127))

{: n2v : cc2v}

