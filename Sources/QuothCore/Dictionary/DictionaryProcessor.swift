import Foundation
import QuothDomain

/// The dictionary's replacement pass, run on every transcript whatever the
/// engine. Reads the current dictionary from the store, so an edit applies to
/// the next dictation.
struct DictionaryProcessor: TranscriptProcessor {
    let store: DictionaryStore

    func process(_ transcript: Transcript) -> Transcript {
        Transcript(text: store.current().replacer.apply(to: transcript.text))
    }
}
