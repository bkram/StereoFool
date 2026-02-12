import Foundation
import CoreAudio

struct AudioDevice: Identifiable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let inputChannels: Int
    let outputChannels: Int

    var hasInput: Bool { inputChannels > 0 }
    var hasOutput: Bool { outputChannels > 0 }
}

enum AudioDeviceError: Error {
    case propertyQueryFailed(OSStatus)
}

enum AudioDevices {
    static func list() throws -> [AudioDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sysObj = AudioObjectID(kAudioObjectSystemObject)
        var status = AudioObjectGetPropertyDataSize(sysObj, &addr, 0, nil, &dataSize)
        guard status == noErr else {
            throw AudioDeviceError.propertyQueryFailed(status)
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(0), count: count)
        status = AudioObjectGetPropertyData(sysObj, &addr, 0, nil, &dataSize, &ids)
        guard status == noErr else {
            throw AudioDeviceError.propertyQueryFailed(status)
        }
        return ids.compactMap { id in
            let name = readCFString(
                objectID: id,
                selector: kAudioObjectPropertyName,
                scope: kAudioObjectPropertyScopeGlobal
            ) ?? "AudioDevice \(id)"
            let uid = readCFString(
                objectID: id,
                selector: kAudioDevicePropertyDeviceUID,
                scope: kAudioObjectPropertyScopeGlobal
            ) ?? "\(id)"
            let inputChannels = readChannelCount(deviceID: id, scope: kAudioDevicePropertyScopeInput)
            let outputChannels = readChannelCount(deviceID: id, scope: kAudioDevicePropertyScopeOutput)
            if inputChannels <= 0 && outputChannels <= 0 {
                return nil
            }
            return AudioDevice(
                id: id,
                uid: uid,
                name: name,
                inputChannels: inputChannels,
                outputChannels: outputChannels
            )
        }
    }

    static func inputDevices() throws -> [AudioDevice] {
        try list().filter { $0.hasInput }
    }

    static func outputDevices() throws -> [AudioDevice] {
        try list().filter { $0.hasOutput }
    }

    private static func readCFString(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &addr,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr, let value else {
            return nil
        }
        return value.takeUnretainedValue() as String
    }

    private static func readChannelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let statusSize = AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &dataSize)
        if statusSize != noErr || dataSize == 0 {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        var mutableSize = dataSize
        let statusData = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &mutableSize, raw)
        if statusData != noErr {
            return 0
        }
        let abl = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        var channels = 0
        for buffer in buffers {
            channels += Int(buffer.mNumberChannels)
        }
        return channels
    }
}
