(fn find_index [list elem]
  "Find the index of an element in a list. Returns nil if the element is not
  found"
  (accumulate [index nil i val (ipairs list) &until (not= index nil)]
    (when (= val elem) i)))

{: find_index}

