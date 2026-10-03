import Foundation

/// The dictation loop's decisions (ADR-007): what a press, a lock, a
/// release, a transcript or a delivery leads to. Pure, so every rule is a
/// unit test; `DictationSession` performs the effects and reports back what
/// happened.
///
/// One recording at a time, but transcriptions overlap: a press while an
/// earlier dictation is still transcribing starts a new recording, and the
/// earlier one still delivers. `inFlight` counts them.
public struct DictationMachine: Equatable {
    public enum State: Equatable, Sendable {
        case idle
        case recording
        case transcribing
    }

    /// Where a dictation's text goes.
    public enum Target: Equatable, Sendable {
        /// The cursor in the app the user was in, or the clipboard when that
        /// isn't possible.
        case cursor
        /// The Quote Card.
        case card
    }

    /// The recording in progress.
    public struct Recording: Equatable, Sendable {
        /// Locked on by a double tap: recording with the hotkey up.
        public var isLocked = false
        /// Where live text goes, when this locked recording has it.
        public var live: Target?
    }

    /// What is true at the moment of a lock, which decides where it goes.
    public struct LockConditions: Equatable, Sendable {
        /// The Quote Card is open.
        public var cardOpen: Bool
        /// Settings sends hands-free dictation to the card.
        public var lockOpensCard: Bool
        /// This build may paste at the cursor (`PasteAccess`).
        public var canInsert: Bool
        /// Settings types text at each pause of a lock.
        public var liveText: Bool
        /// The microphone changed during the double tap itself.
        public var routeChanged: Bool

        public init(cardOpen: Bool, lockOpensCard: Bool, canInsert: Bool, liveText: Bool, routeChanged: Bool) {
            self.cardOpen = cardOpen
            self.lockOpensCard = lockOpensCard
            self.canInsert = canInsert
            self.liveText = liveText
            self.routeChanged = routeChanged
        }
    }

    /// Why a dictation put nothing at the cursor. The session pairs it with
    /// the error it caught, for observers.
    public enum Failure: Equatable, Sendable {
        /// The microphone didn't start.
        case captureFailedToStart
        /// The capture couldn't be finished: the route changed mid-recording.
        case captureLost
        /// Nothing, or nothing but silence, was recorded.
        case noSpeech
        /// The gesture discarded the recording: a short tap, a chord, a
        /// hotkey switch.
        case cancelled
        /// The transcriber threw.
        case transcriptionFailed
        /// The text was refused at delivery.
        case notDelivered(DeliveryError)
    }

    /// How a finished capture turned out.
    public enum Capture: Equatable, Sendable {
        /// The capture was lost: no partial recording is delivered.
        case lost
        /// Samples, and whether they hold speech.
        case audio(hasSpeech: Bool)
    }

    /// How a locked recording's live text ended.
    public struct LiveEnding: Equatable, Sendable {
        /// Characters transcribed over every segment.
        public var chars: Int
        /// The first delivery failure, which stopped typing.
        public var deliveryError: DeliveryError?
        /// A segment failed to transcribe.
        public var transcriptionFailed: Bool

        public init(chars: Int, deliveryError: DeliveryError? = nil, transcriptionFailed: Bool = false) {
            self.chars = chars
            self.deliveryError = deliveryError
            self.transcriptionFailed = transcriptionFailed
        }
    }

    /// Instructions for `DictationSession`, carried out in order.
    public enum Effect: Equatable, Sendable {
        /// Tell observers a recording started, and note what has focus.
        case started
        /// Tell observers the recording is locked on.
        case locked
        /// Tell observers the capture is being transcribed.
        case transcribing
        /// Tell observers the dictation reached its target.
        case finished
        /// Tell observers nothing reached the cursor.
        case failed(Failure)
        /// The gesture should ignore the rest of this hold.
        case abandonPress
        /// End the lock as a tap of the hotkey would, on the next turn of
        /// the run loop.
        case endLock(reason: String)
        /// Stop the microphone and collect the recording.
        case finishCapture(keepBeforeRouteChange: Bool)
        /// Stop the microphone and throw the recording away.
        case stopCapture
        case openCard
        /// Transcribe each segment of the locked recording at its pause.
        case startLive(Target)
        /// Transcribe the rest of the recording and wait for every segment.
        case finishLive
        /// Deliver nothing more of the live text.
        case cancelLive
        /// Call `liveCancelled` once the segments already running are done.
        case awaitLive
        /// Transcribe the recording.
        case transcribe
        /// "scratch that": remove what was last delivered to the target.
        case scratchLast(Target)
        case deliver(Target)
        /// Keep the text for Copy and Fix Last Dictation.
        case remember
    }

    public private(set) var recording: Recording?
    /// Transcriptions started and not yet delivered or failed, including
    /// a released capture still being looked at.
    public private(set) var inFlight = 0

    public init() {}

    public var state: State {
        if recording != nil { return .recording }
        return inFlight > 0 ? .transcribing : .idle
    }

    public var isLocked: Bool { recording?.isLocked ?? false }

    // MARK: The gesture

    /// The hotkey went down and the session tried to start the microphone,
    /// as it does on every press, even while an earlier dictation is still
    /// transcribing.
    public mutating func pressed(captureStarted: Bool) -> [Effect] {
        guard captureStarted else {
            // No recording: the rest of this hold can't lock or transcribe.
            return [.failed(.captureFailedToStart), .abandonPress]
        }
        recording = Recording()
        return [.started]
    }

    /// A double tap locked the recording on; capture carries on unchanged.
    public mutating func locked(_ conditions: LockConditions) -> [Effect] {
        guard var recording else { return [] }
        recording.isLocked = true
        var effects: [Effect] = []
        // There is nothing more to record from a microphone that changed
        // during the double tap, so the lock ends straight away.
        if conditions.routeChanged {
            effects.append(.endLock(reason: "the microphone changed"))
        }
        // The card takes the lock when it is open, when Settings says so,
        // and in a build that can't paste, where it beats copying the whole
        // lock at the end.
        let toCard = conditions.cardOpen || conditions.lockOpensCard || !conditions.canInsert
        if toCard { effects.append(.openCard) }
        if conditions.liveText, toCard || conditions.canInsert {
            let target: Target = toCard ? .card : .cursor
            recording.live = target
            effects.append(.startLive(target))
        }
        self.recording = recording
        effects.append(.locked)
        return effects
    }

    /// The hotkey ended the recording. A locked one keeps what came before
    /// a microphone change; push-to-talk loses it.
    public mutating func released() -> [Effect] {
        guard recording != nil else { return [] }
        return [.finishCapture(keepBeforeRouteChange: isLocked)]
    }

    /// The capture asked for by `finishCapture`.
    public mutating func captured(_ capture: Capture) -> [Effect] {
        guard let recording else { return [] }
        self.recording = nil
        guard case .audio(let hasSpeech) = capture else {
            return recording.live != nil ? [.cancelLive, .failed(.captureLost)] : [.failed(.captureLost)]
        }
        if recording.live != nil {
            inFlight += 1
            return [.transcribing, .finishLive]
        }
        // Whisper invents words ("you", "Thank you.") for silence, so a
        // press with nothing said transcribes nothing.
        guard hasSpeech else {
            return [.transcribing, .failed(.noSpeech)]
        }
        inFlight += 1
        return [.transcribing, .transcribe]
    }

    /// The gesture discarded the recording: stop and transcribe nothing.
    /// Live text already typed stays.
    public mutating func cancelled() -> [Effect] {
        guard let recording else { return [] }
        self.recording = nil
        var effects: [Effect] = [.stopCapture]
        if recording.live != nil {
            // Its running segments hold the transcriber; a model switch
            // waits for them, so they count as in flight.
            inFlight += 1
            effects += [.cancelLive, .awaitLive]
        }
        effects.append(.failed(.cancelled))
        return effects
    }

    /// The input route changed (a headset connected): a locked recording
    /// ends and keeps what came before; push-to-talk discards on release.
    public func routeChanged() -> [Effect] {
        isLocked ? [.endLock(reason: "the microphone changed")] : []
    }

    // MARK: After the capture

    /// A push-to-talk transcript is ready. While the Quote Card is open,
    /// every dictation goes into it.
    public func transcribed(scratchesPrevious: Bool, cardOpen: Bool) -> [Effect] {
        let target: Target = cardOpen ? .card : .cursor
        return scratchesPrevious ? [.scratchLast(target), .deliver(target)] : [.deliver(target)]
    }

    /// The transcript asked for by `deliver` was delivered, or refused.
    /// Text refused in a password field is never remembered.
    public mutating func delivered(_ error: DeliveryError?) -> [Effect] {
        inFlight -= 1
        var effects: [Effect] = error == .secureField ? [] : [.remember]
        effects.append(error.map { .failed(.notDelivered($0)) } ?? .finished)
        return effects
    }

    /// The transcriber threw on a push-to-talk recording.
    public mutating func transcriptionFailed() -> [Effect] {
        inFlight -= 1
        return [.failed(.transcriptionFailed)]
    }

    /// A locked recording's live text has every segment in.
    public mutating func liveFinished(_ ending: LiveEnding) -> [Effect] {
        inFlight -= 1
        var effects: [Effect] = ending.deliveryError == .secureField ? [] : [.remember]
        if let error = ending.deliveryError {
            effects.append(.failed(.notDelivered(error)))
        } else if ending.chars == 0 {
            effects.append(.failed(ending.transcriptionFailed ? .transcriptionFailed : .noSpeech))
        } else {
            effects.append(.finished)
        }
        return effects
    }

    /// The segments of a cancelled lock have stopped.
    public mutating func liveCancelled() {
        inFlight -= 1
    }
}
