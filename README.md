# ahk-midi-wrapper
MIDI wrapper for Autohotkey v2. The script supports these events:
* note on
* note off
* control change.

## Usage
To use the wrapper you need to import it into your script and keep your script running so that it can react to events
(otherwise your script will set everything up but then finish and exit):
```autohotkey
#Include "midi_wrapper.ahk"
Persistent
```

### Triggering code when an event is fired
For each event type you register a method that will be run each time an event of that type is received.
You must also use the ```midiOpenDeviceForInput()``` method to start monitoring a MIDI device.
See [examples/midi_events.ahk](examples/midi_events.ahk) for a complete example.

#### Registering callbacks
There is an array for each event type, simply add a callback method to the appropriate array.

##### Note on events
```autohotkey
onNoteOnEvent(channel, noteNum, velocity) {
    MsgBox('Note on received for note ' . noteNum . ' on channel ' . channel . ' with velocity ' . velocity)
}
midiNoteOnCallbacks.push(onNoteOnEvent)
```
the `onNoteOnEvent` method will run every time a note on event is received.

##### Note off events
```autohotkey
onNoteOffEvent(channel, noteNum, velocity) {
    MsgBox('Note off received for note ' . noteNum . ' on channel ' . channel . ' with velocity ' . velocity)
}
midiNoteOffCallbacks.push(onNoteOffEvent)
```

Some MIDI devices don't send "proper" note off events: instead they send a note on event with `velocity=0`.
You can use the [examples/midi_events.ahk](examples/midi_events.ahk) script to test your device and see what happens.
If your device does send a note on event with `velocity=0` then you can check the velocity to work out whether the event
is actually a note on or off.

```autohotkey
onNoteOnEvent(channel, noteNum, velocity) {
    if (velocity == 0) {
        MsgBox('Note off received for note ' . noteNum . ' on channel ' . channel)
    } else {
        MsgBox('Note on received for note ' . noteNum . ' on channel ' . channel . ' with velocity ' . velocity)
    }
}
midiNoteOnCallbacks.push(onNoteOnEvent)
```


##### Controller change events
```autohotkey
onControlChangeEvent(channel, controllerId, value) {
    MsgBox('Control change received for controller ID ' . controllerId . ' on channel ' . channel . ' with value ' . value)
}
midiControlChangeCallbacks.push(onControlChangeEvent)
```


#### midiOpenDeviceForInput(deviceIndex, ccDebounceIntervalMs)
You must call the ```midiOpenDeviceForInput``` method to start listening for MIDI events.

_Parameters_:
* deviceIndex: the 0-based index of the device
* ccDebounceIntervalMs: the debounce interval (in ms) for control change events. Use 0 to prevent debouncing


Controller change events can be [debounced](https://dev.to/aneeqakhan/throttling-and-debouncing-explained-1ocb). This is
because controller change events are often sent by rotary controls or similar: if a rotary control is turned from 1 to
30 then separate events are sent for every new value (2, 3, 4, 5, ..., 30). If this is desired, use 0 as the value of
```ccDebounceIntervalMs```. If you are only interested in the final value of the control (30 in this case) then
specifying a suitable debounce interval will prevent the events for intermediate values from triggering your callback.
The suitable interval depends on the hardware and user (i.e. how quickly they move the control), but 600ms is a
good starting point.


#### Technical notes
##### Threading
Each callback is run in its own thread.

##### Multiple callbacks
More than one callback can be added for each event type. They will be called in the order in which they appear in the
array.

##### Device sleep/modern standby
When a device (e.g. laptop) resumes from sleep (properly now referred to as
[Modern Standby](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby)), MIDI
events are no longer received by the wrapper. The wrapper tries to restart the monitoring when the device resumes,
but in practice it does not always seem to be notified that the device has resumed.


### Helper methods
These methods give details about the available MIDI devices.
See [examples/helper_methods.ahk](examples/helper_methods.ahk)

#### midiGetDeviceCount()
Returns the number of available MIDI devices.

_Returns_:
An integer (0 or more) which is the count of the number of available MIDI devices.
```autohotkey
deviceCount := midiGetDeviceCount()
```

#### midiGetDeviceName(deviceIndex)
Returns the name of the specified device.

_Parameters_:
* deviceIndex: the 0-based index of the device

_Returns_:
A string containing the name of the MIDI device.

```autohotkey
firstDeviceName := midiGetDeviceName(0)
```

#### midiGetAllDeviceNames()
Returns an array of the names of all the available MIDI devices.

_Returns_:
An array with one element for each MIDI device.

