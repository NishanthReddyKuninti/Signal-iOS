//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import AVFoundation
import SignalServiceKit

public struct AudioSource: Hashable {

    public let image: UIImage
    public let localizedName: String
    public let portDescription: AVAudioSessionPortDescription?

    // The built-in loud speaker / aka speakerphone
    public let isBuiltInSpeaker: Bool

    // The built-in quiet speaker, aka the normal phone handset receiver earpiece
    public let isBuiltInEarPiece: Bool

    public init(localizedName: String, image: UIImage, isBuiltInSpeaker: Bool, isBuiltInEarPiece: Bool, portDescription: AVAudioSessionPortDescription? = nil) {
        self.localizedName = localizedName
        self.image = image
        self.isBuiltInSpeaker = isBuiltInSpeaker
        self.isBuiltInEarPiece = isBuiltInEarPiece
        self.portDescription = portDescription
    }

    public init(portDescription: AVAudioSessionPortDescription) {

        let isBuiltInEarPiece = portDescription.portType == AVAudioSession.Port.builtInMic

        // portDescription.portName works well for BT linked devices, but if we are using
        // the built in mic, we have "iPhone Microphone" which is a little awkward.
        // In that case, instead we prefer just the model name e.g. "iPhone" or "iPad"
        let localizedName = isBuiltInEarPiece ? UIDevice.current.localizedModel : portDescription.portName

        self.init(localizedName: localizedName,
                  image: Theme.iconImage(.audioCall), // TODO
                  isBuiltInSpeaker: false,
                  isBuiltInEarPiece: isBuiltInEarPiece,
                  portDescription: portDescription)
    }

    // Speakerphone is handled separately from the other audio routes as it doesn't appear as an "input"
    public static var builtInSpeaker: AudioSource {
        return self.init(localizedName: NSLocalizedString("AUDIO_ROUTE_BUILT_IN_SPEAKER", comment: "action sheet button title to enable built in speaker during a call"),
                         image: Theme.iconImage(.audioCall), //TODO
                         isBuiltInSpeaker: true,
                         isBuiltInEarPiece: false)
    }

    // MARK: Hashable

    public static func ==(lhs: AudioSource, rhs: AudioSource) -> Bool {
        // Simply comparing the `portDescription` vs the `portDescription.uid`
        // caused multiple instances of the built in mic to turn up in a set.
        if lhs.isBuiltInSpeaker && rhs.isBuiltInSpeaker {
            return true
        }

        if lhs.isBuiltInSpeaker || rhs.isBuiltInSpeaker {
            return false
        }

        guard let lhsPortDescription = lhs.portDescription else {
            owsFailDebug("only the built in speaker should lack a port description")
            return false
        }

        guard let rhsPortDescription = rhs.portDescription else {
            owsFailDebug("only the built in speaker should lack a port description")
            return false
        }

        return lhsPortDescription.uid == rhsPortDescription.uid
    }

    public func hash(into hasher: inout Hasher) {
        guard let portDescription = self.portDescription else {
            assert(self.isBuiltInSpeaker)
            hasher.combine("Built In Speaker")
            return
        }

        hasher.combine(portDescription.uid)
    }
}
