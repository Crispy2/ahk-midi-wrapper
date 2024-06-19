#Include "../midi_wrapper.ahk"

deviceCount := midiGetDeviceCount()
MsgBox('Number of MIDI devices: ' . deviceCount)

if (deviceCount > 0) {
    firstDeviceName := midiGetDeviceName(0)
    MsgBox('The first MIDI device is called: ' . firstDeviceName)

    allDeviceNames := midiGetAllDeviceNames()
    deviceNameListStr := ''
    separator := ''
    for deviceName in allDeviceNames {
        deviceNameListStr := deviceNameListStr . separator . deviceName
        separator := '\n'
   }

    MsgBox('Here are all the MIDI devices: ' . deviceNameListStr)
}