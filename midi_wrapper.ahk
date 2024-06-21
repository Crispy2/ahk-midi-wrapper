#SingleInstance

OnExit midi_InternalTidyUp

MIDI_NO_DEVICE := -1

midi_InternalOpenDeviceHandle := MIDI_NO_DEVICE
midi_InternalOpenDeviceIndex := MIDI_NO_DEVICE
midi_InternalCcDebounceIntervalMs := 0

midi_InternalNoteOnCallbacks := Array()
midi_InternalNoteOffCallbacks := Array()
midi_InternalControlChangeCallbacks := Array()

; Returns the number of MIDI devices
midiGetDeviceCount() {
	return DllCall("winmm.dll\midiInGetNumDevs")
}

/*
    Returns the name of a given MIDI device.

    deviceIndex: the 0-based index of the device
*/
midiGetDeviceName(deviceIndex) {
	offsetWordStr := 64
	midiSize := offsetWordStr + 18
	midiInCaps := Buffer(midiSize, 0)

	/*
	MMRESULT midiInGetDevCapsA(
	  UINT_PTR      uDeviceID,
	  LPMIDIINCAPSA pmic,
	  UINT          cbmic
	);
	*/
	/*
	typedef struct {
	  WORD      wMid;
	  WORD      wPid;
	  MMVERSION vDriverVersion;
	  TCHAR     szPname[MAXPNAMELEN];
	  DWORD     dwSupport;
	} MIDIINCAPS
	*/
	result := DllCall("winmm.dll\midiInGetDevCapsA", "UInt", deviceIndex, "Ptr", midiInCaps, "UInt", midiSize)
	if (result) {
		throw OSError('DLL midiInGetDevCapsA result: ' . result, result)
	}
	return StrGet(midiInCaps.Ptr + 8, offsetWordStr, 'CP0')
}

/*
    Returns an array with the names of all MIDI devices
*/
midiGetAllDeviceNames() {
	deviceCount := midiGetDeviceCount()
	deviceNames := Array()

	loop deviceCount {
		deviceNames.Push(midiGetDeviceName(A_Index-1))
	}

	return deviceNames
}

/*
    Adds a callback for note on events.

    callback: function with parameters (channel, noteNum, velocity)
*/
midiAddNoteOnCallback(callback) {
    midi_InternalValidateFunctionParameterCount(callback, 3, 3, 'Invalid number of parameters. Requires callback(channel, noteNum, velocity)')
    midi_InternalNoteOnCallbacks.push(callback)
}

/*
    Adds a callback for note off events.

    callback: function with parameters (channel, noteNum, velocity)
*/
midiAddNoteOffCallback(callback) {
    midi_InternalValidateFunctionParameterCount(callback, 3, 3, 'Invalid number of parameters. Requires callback(channel, noteNum, velocity)')
    midi_InternalNoteOffCallbacks.push(callback)
}

/*
    Adds a callback for control change events.

    callback: function with parameters (channel, controllerId, value)
*/
midiAddControlChangeCallback(callback) {
    midi_InternalValidateFunctionParameterCount(callback, 3, 3, 'Invalid number of parameters. Requires callback(channel, controllerId, value)')
    midi_InternalControlChangeCallbacks.push(callback)
}

/*
    Opens a MIDI device for input.

    deviceIndex: the 0-based index of the device
    ccDebounceIntervalMs: the debounce interval (in ms) for control change events. A control change event will not be
                            output if another control change event occurs within this number of milliseconds
*/
midiOpenDeviceForInput(deviceIndex, ccDebounceIntervalMs) {
	global midi_InternalCcDebounceIntervalMs, midi_InternalOpenDeviceIndex
	midi_InternalCcDebounceIntervalMs := ccDebounceIntervalMs

	CALLBACK_FUNCTION := 0x30000
	deviceHandleBuffer := Buffer(4, 0)

	/*
	MMRESULT midiInOpen(
	  LPHMIDIIN phmi,
	  UINT      uDeviceID,
	  DWORD_PTR dwCallback,
	  DWORD_PTR dwInstance,
	  DWORD     fdwOpen
	);
	*/
	result := DllCall("winmm.dll\midiInOpen", 'Ptr', deviceHandleBuffer, 'UInt', deviceIndex, 'UInt', CallbackCreate(midi_InternalOnMidiMessageCallback), 'UInt', 0, 'UInt', CALLBACK_FUNCTION, 'UInt')
	if (result) {
		throw OSError('DLL midiInOpen result: ' . result, result)
	}

	deviceHandle := NumGet(deviceHandleBuffer, 'int')

	result := DllCall("winmm.dll\midiInStart", 'UInt', deviceHandle, 'UInt')
	if (result) {
		throw OSError('DLL midiInStart result: ' . result, result)
	}

	midi_InternalOpenDeviceIndex := deviceIndex
	midi_InternalMonitorPowerResumeMessages()
	return deviceHandle
}

; Stop using a MIDI device for input
midiCloseDeviceForInput(deviceHandle) {
	DllCall("winmm.dll\midiInClose", 'UInt', deviceHandle, 'UInt')
}

; For internal use - called when the script exits to ensure that an open device is closed
midi_InternalTidyUp(exitReason, exitCode) {
	global midi_InternalOpenDeviceHandle, midi_InternalOpenDeviceIndex
	if (midi_InternalOpenDeviceIndex !== MIDI_NO_DEVICE) {
		midiCloseDeviceForInput(midi_InternalOpenDeviceHandle)
		midi_InternalOpenDeviceIndex := MIDI_NO_DEVICE
	}
}

; For internal use - called when a MIDI message is received
midi_InternalOnMidiMessageCallback(hMidiIn, msg, instance, midiPayload, midiTimestamp) {
	MIM_OPEN := 961
	MIM_CLOSE := 962
	MIM_DATA := 963
	MIM_LONGDATA := 964
	MIM_MOREDATA := 972

	NOTE_ON := 9
	NOTE_OFF := 8
	CONTROL_CHANGE := 0xB
	PROGRAM_CHANGE := 0xC

	global midi_InternalCcDebounceIntervalMs

	if (msg == MIM_DATA) {
		statusbyte  	:=  midiPayload & 0xFF
		msgType			:=  statusbyte >> 4
		channel        	:= (statusbyte & 0x0f) + 1
		data1         	:= (midiPayload >> 8) & 0xFF
		data2         	:= (midiPayload >> 16) & 0xFF

		if (msgType == NOTE_ON) {
			noteNum := data1
			velocity := data2

			for callback in midi_InternalNoteOnCallbacks {
				SetTimer midi_InternalCreateNoteCallbackClosure(callback, channel, noteNum, velocity), -1
			}
		}
		if (msgType == NOTE_OFF) {
			noteNum := data1
			velocity := data2

			for callback in midi_InternalNoteOffCallbacks {
				SetTimer midi_InternalCreateNoteCallbackClosure(callback, channel, noteNum, velocity), -1
			}
		}
		if (msgType == CONTROL_CHANGE) {
			controllerId := data1
			static lastTriggerByControllerId := Map()

			lastTriggerByControllerId.Set(controllerId, A_TickCount)

			SetTimer debounce, -midi_InternalCcDebounceIntervalMs

			debounce() {
				lastTrigger := lastTriggerByControllerId.get(controllerId, 0)

				if (((A_TickCount - lastTrigger) > midi_InternalCcDebounceIntervalMs)) {
					for callback in midi_InternalControlChangeCallbacks {
						SetTimer midi_InternalCreateControllerCallbackClosure(callback, channel, controllerId, data2), -1
					}
				}
			}
		}
	}
}

; For internal use - used to create a closure for a callback for MIDI note events
midi_InternalCreateNoteCallbackClosure(callback, channel, noteNum, velocity) {
	wrapper() {
		callback(channel, noteNum, velocity)
	}
	return wrapper
}

; For internal use - used to create a closure for a callback for MIDI control change events
midi_InternalCreateControllerCallbackClosure(callback, channel, controllerId, value) {
	wrapper() {
		callback(channel, controllerId, value)
	}
	return wrapper
}

/*
    For internal use - starts monitoring WM_POWERBROADCAST broadcast.
    The library tries to re-open the MIDI device after resuming from sleep
*/
midi_InternalMonitorPowerResumeMessages() {
	DEVICE_NOTIFY_WINDOW_HANDLE := 0
	WM_POWERBROADCAST := 0x218

	static monitoringStarted := false

	if (!monitoringStarted) {
		/*
		HPOWERNOTIFY RegisterSuspendResumeNotification(
		  [in] HANDLE hRecipient,
		  [in] DWORD  Flags
		);
		*/
		DllCall('RegisterSuspendResumeNotification', 'UInt', A_ScriptHwnd, 'UInt', DEVICE_NOTIFY_WINDOW_HANDLE, 'UInt')

		OnMessage(WM_POWERBROADCAST, midi_InternalOnPowerBroadcastMessage)
		monitoringStarted := True
	}
}

; For internal use - called when a WM_POWERBROADCAST message is received
midi_InternalOnPowerBroadcastMessage(wParam, lParam, msg, hwnd) {
/*
LRESULT CALLBACK WindowProc(
  HWND   hwnd,    // handle to window
  UINT   uMsg,    // WM_POWERBROADCAST
  WPARAM wParam,  // power-management event
  LPARAM lParam   // function-specific data
);
*/
	PBT_APMPOWERSTATUSCHANGE := 16
	PBT_APMRESUMEAUTOMATIC := 18
	PBT_APMRESUMESUSPEND := 7
	PBT_APMSUSPEND := 4
	PBT_POWERSETTINGCHANGE := 32787

	if (wParam == PBT_APMRESUMEAUTOMATIC) {
		if (midi_InternalOpenDeviceIndex != MIDI_NO_DEVICE) {

			midiCloseDeviceForInput(midi_InternalOpenDeviceHandle)
			midiOpenDeviceForInput(midi_InternalOpenDeviceIndex, midi_InternalCcDebounceIntervalMs)
		}
	}
}

midi_InternalValidateFunctionParameterCount(funcObj, minCount, maxCount, errorMsg) {
    if (funcObj.minParams!=minCount || funcObj.maxParams!=maxCount) {
        throw ValueError(errorMsg)
    }
}