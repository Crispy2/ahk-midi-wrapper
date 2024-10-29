#Include "../midi_wrapper.ahk"
Persistent  ; This keeps this script running so it can keep reacting to events. It must be stopped manually

DEVICE_INDEX_TO_USE := 0        ; The 0-based index of the device to open

; This method will be called when a note on event is received
onNoteOnEvent(channel, noteNum, velocity) {
    MsgBox('Note on received for note ' . noteNum . ' on channel ' . channel . ' with velocity ' . velocity)
}

; This method will be called when a note off event is received
onNoteOffEvent(channel, noteNum, velocity) {
    MsgBox('Note off received for note ' . noteNum . ' on channel ' . channel . ' with velocity ' . velocity)
}

; This method will be called when a control change event is received
onControlChangeEvent(channel, controllerId, value) {
    MsgBox('Control change received for controller ID ' . controllerId . ' on channel ' . channel . ' with value ' . value)
}

; Register the callbacks
midiAddNoteOnCallback(onNoteOnEvent)
midiAddNoteOffCallback(onNoteOffEvent)
midiAddControlChangeCallback(onControlChangeEvent)

; Open the MIDI device for input (i.e. start receiving the events)
midiOpenDeviceForInput(DEVICE_INDEX_TO_USE, 600)