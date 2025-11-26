import AudioToolbox
import Combine
import CoreAudio
import Foundation

/// Represents an audio output device
struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transportType: AudioTransportType
    let isDefault: Bool

    var icon: String {
        // Check device name for specific products
        let lowercaseName = name.lowercased()

        if lowercaseName.contains("airpods pro") {
            return "airpodspro"
        } else if lowercaseName.contains("airpods max") {
            return "airpodsmax"
        } else if lowercaseName.contains("airpods") {
            return "airpods.gen3"
        } else if lowercaseName.contains("homepod") {
            return "homepodmini"
        } else if lowercaseName.contains("beats") {
            return "beats.headphones"
        }

        // Fall back to transport type
        switch transportType {
        case .bluetooth, .bluetoothLE:
            return "headphones"
        case .builtIn:
            return "speaker.wave.2"
        case .usb:
            return "cable.connector"
        case .displayPort, .hdmi:
            return "display"
        case .airPlay:
            return "airplayaudio"
        default:
            return "speaker.wave.2"
        }
    }
}

enum AudioTransportType {
    case builtIn
    case bluetooth
    case bluetoothLE
    case usb
    case airPlay
    case displayPort
    case hdmi
    case unknown

    init(from transportType: UInt32) {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            self = .builtIn
        case kAudioDeviceTransportTypeBluetooth:
            self = .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE:
            self = .bluetoothLE
        case kAudioDeviceTransportTypeUSB:
            self = .usb
        case kAudioDeviceTransportTypeAirPlay:
            self = .airPlay
        case kAudioDeviceTransportTypeDisplayPort:
            self = .displayPort
        case kAudioDeviceTransportTypeHDMI:
            self = .hdmi
        default:
            self = .unknown
        }
    }
}

/// Event-driven audio output monitor using CoreAudio
class AudioOutputManager: ObservableObject {
    static let shared = AudioOutputManager()

    @Published var currentDevice: AudioDevice?
    @Published var outputDevices: [AudioDevice] = []
    @Published var volume: Float = 0.0
    @Published var isMuted: Bool = false

    private var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?
    private var volumeListenerBlocks: [(AudioDeviceID, AudioObjectPropertyListenerBlock)] = []
    private var pollTimer: Timer?

    private init() {
        setupListeners()
        refreshDevices()
        refreshVolume()
        startVolumePolling()
    }

    deinit {
        removeListeners()
        pollTimer?.invalidate()
    }

    // MARK: - Listeners

    private func setupListeners() {
        // Listen for default output device changes
        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        defaultOutputListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
                self?.refreshVolume()
                self?.setupVolumeListeners()
            }
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            DispatchQueue.main,
            defaultOutputListenerBlock!
        )

        // Set up volume listeners for current device
        setupVolumeListeners()
    }

    private func setupVolumeListeners() {
        // Remove old listeners
        removeVolumeListeners()

        let deviceID = getDefaultOutputDeviceID()
        guard deviceID != 0 else { return }

        // Listen on multiple channels (master, left, right)
        let channels: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]
        let selectors: [AudioObjectPropertySelector] = [
            kAudioDevicePropertyVolumeScalar,
            kAudioDevicePropertyMute
        ]

        for selector in selectors {
            for channel in channels {
                var address = AudioObjectPropertyAddress(
                    mSelector: selector,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: channel
                )

                guard AudioObjectHasProperty(deviceID, &address) else { continue }

                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    DispatchQueue.main.async {
                        self?.refreshVolume()
                    }
                }

                let status = AudioObjectAddPropertyListenerBlock(
                    deviceID,
                    &address,
                    DispatchQueue.main,
                    block
                )

                if status == noErr {
                    volumeListenerBlocks.append((deviceID, block))
                }
            }
        }
    }

    private func removeVolumeListeners() {
        for (deviceID, block) in volumeListenerBlocks {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        }
        volumeListenerBlocks.removeAll()
    }

    // Fallback polling for volume changes (some devices don't notify properly)
    private func startVolumePolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshVolume()
        }
    }

    private func removeListeners() {
        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        if let block = defaultOutputListenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultOutputAddress,
                DispatchQueue.main,
                block
            )
        }

        removeVolumeListeners()
    }

    // MARK: - Device Discovery

    func refreshDevices() {
        let defaultDeviceID = getDefaultOutputDeviceID()

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return }

        var devices: [AudioDevice] = []

        for deviceID in deviceIDs {
            // Check if device has output streams
            guard hasOutputStreams(deviceID) else { continue }

            if let device = createAudioDevice(deviceID, isDefault: deviceID == defaultDeviceID) {
                devices.append(device)
            }
        }

        DispatchQueue.main.async {
            self.outputDevices = devices.sorted { $0.isDefault && !$1.isDefault }
            self.currentDevice = devices.first { $0.isDefault }
        }
    }

    private func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)

        return status == noErr && dataSize > 0
    }

    private func createAudioDevice(_ deviceID: AudioDeviceID, isDefault: Bool) -> AudioDevice? {
        guard let name = getDeviceName(deviceID) else { return nil }
        let transportType = getTransportType(deviceID)

        return AudioDevice(
            id: deviceID,
            name: name,
            transportType: transportType,
            isDefault: isDefault
        )
    }

    private func getDefaultOutputDeviceID() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        return deviceID
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        return status == noErr ? name as String? : nil
    }

    private func getTransportType(_ deviceID: AudioDeviceID) -> AudioTransportType {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &transportType
        )

        return status == noErr ? AudioTransportType(from: transportType) : .unknown
    }

    // MARK: - Volume Control

    func refreshVolume() {
        guard let deviceID = currentDevice?.id ?? Optional(getDefaultOutputDeviceID()) else { return }

        // Get volume
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Try master channel first
        if !AudioObjectHasProperty(deviceID, &volumeAddress) {
            volumeAddress.mElement = 1  // Try channel 1
        }

        var volume: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)

        if AudioObjectHasProperty(deviceID, &volumeAddress) {
            AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &dataSize, &volume)
        }

        // Get mute state
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var muted: UInt32 = 0
        dataSize = UInt32(MemoryLayout<UInt32>.size)

        if AudioObjectHasProperty(deviceID, &muteAddress) {
            AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &dataSize, &muted)
        }

        DispatchQueue.main.async {
            self.volume = volume
            self.isMuted = muted != 0
        }
    }

    func setVolume(_ newVolume: Float) {
        guard let deviceID = currentDevice?.id else { return }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if !AudioObjectHasProperty(deviceID, &volumeAddress) {
            volumeAddress.mElement = 1
        }

        var volume = newVolume
        let dataSize = UInt32(MemoryLayout<Float32>.size)

        AudioObjectSetPropertyData(deviceID, &volumeAddress, 0, nil, dataSize, &volume)

        DispatchQueue.main.async {
            self.volume = newVolume
        }
    }

    func setMuted(_ muted: Bool) {
        guard let deviceID = currentDevice?.id else { return }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &muteAddress) else { return }

        var muteValue: UInt32 = muted ? 1 : 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)

        AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, dataSize, &muteValue)

        DispatchQueue.main.async {
            self.isMuted = muted
        }
    }

    // MARK: - Device Switching

    func setDefaultOutputDevice(_ device: AudioDevice) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = device.id
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &deviceID
        )
    }
}
