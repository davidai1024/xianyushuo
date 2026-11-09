import AVFoundation
import CoreMedia

/// A device-specific, audio-only session. An AVAudioEngine on the default route
/// can combine a Bluetooth microphone with a separate output into an aggregate
/// device. Rebuilding that aggregate on an output switch can strand its input.
final class DeviceAudioCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    let format: AVAudioFormat
    let graphName: String
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let controlQueue = DispatchQueue(label: "im.muse.dianyu.device-capture")
    private let bufferQueue = DispatchQueue(label: "im.muse.dianyu.device-pcm", qos: .userInitiated)
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    var isRunning: Bool { session.isRunning }

    init(device: AVCaptureDevice, bluetooth: Bool) throws {
        guard let native = CMAudioFormatDescriptionGetStreamBasicDescription(device.activeFormat.formatDescription),
              let format = AVAudioFormat(standardFormatWithSampleRate: native.pointee.mSampleRate,
                                         channels: native.pointee.mChannelsPerFrame) else {
            throw AppError.message("无法读取所选麦克风的音频格式。")
        }
        self.format = format
        graphName = bluetooth ? "bluetooth_input" : "device_input"
        super.init()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw AppError.message("无法启动所选麦克风。")
        }
        session.addInput(input)
        output.audioSettings = format.settings
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: bufferQueue)
    }

    func start() {
        controlQueue.async { [session] in session.startRunning() }
    }

    func stop() {
        controlQueue.sync {
            output.setSampleBufferDelegate(nil, queue: nil)
            session.stopRunning()
            for input in session.inputs { session.removeInput(input) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0,
              let description = CMSampleBufferGetFormatDescription(sample),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let actual = AVAudioFormat(streamDescription: stream),
              actual.commonFormat == .pcmFormatFloat32,
              actual.sampleRate == format.sampleRate,
              actual.channelCount == format.channelCount,
              !actual.isInterleaved || actual.channelCount == 1,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        pcm.frameLength = AVAudioFrameCount(frames)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                           into: pcm.mutableAudioBufferList) == noErr else { return }
        onBuffer?(pcm)
    }
}
