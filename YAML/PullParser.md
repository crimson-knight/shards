# class YAML::PullParser

A pull parser allows parsing a YAML document by events.

When creating an instance, the parser is positioned in
the first event. To get the event kind invoke `kind`.
If the event is a scalar you can invoke `value` to get
its **string** value. Other methods like `tag`, `anchor`
and `scalar_style` let you inspect other information from events.

Invoking `read_next` reads the next event.

## Instance Methods

### `each_in_mapping`

Iterates a mapping, yielding on each new entry until the mapping is
terminated.

### `each_in_sequence`

Iterates a sequence, yielding on each new entry until the sequence is
terminated.

### `read_empty_or`

