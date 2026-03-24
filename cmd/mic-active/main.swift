import CoreAudio

var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
let count = Int(size) / MemoryLayout<AudioDeviceID>.size
var devices = [AudioDeviceID](repeating: 0, count: count)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)

for device in devices {
    var streamAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: 0)
    var streamSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &streamAddress, 0, nil, &streamSize) == noErr,
          streamSize > 0 else { continue }
    let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(streamSize))
    defer { bufferList.deallocate() }
    guard AudioObjectGetPropertyData(device, &streamAddress, 0, nil, &streamSize, bufferList) == noErr else { continue }
    guard bufferList.pointee.mNumberBuffers > 0 && bufferList.pointee.mBuffers.mNumberChannels > 0 else { continue }

    var isAliveAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: 0)
    var isRunning: UInt32 = 0
    var runSize = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(device, &isAliveAddress, 0, nil, &runSize, &isRunning) == noErr else { continue }

    if isRunning == 1 { exit(0) }
}
exit(1)
