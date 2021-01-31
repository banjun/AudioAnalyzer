import CoreMedia

extension AudioStreamBasicDescription {
    var formatDescriptionString: String {
        [
            String(mSampleRate) + "Hz",
            String(mBytesPerFrame) + "bytes/f",
            String(mBitsPerChannel) + "bits/ch",
            // String($0.mChannelsPerFrame) + "ch/f",
            mFormatFlags & kAudioFormatFlagIsFloat > 0 ? "Float" : "Integer",
            mFormatFlags & kAudioFormatFlagIsBigEndian > 0 ? "BE" : "LE",
            mFormatFlags & kAudioFormatFlagIsSignedInteger > 0 ? "Signed" : "Unsigned",
            mFormatFlags & kAudioFormatFlagIsPacked > 0 ? "Packed" : "NotPacked",
            mFormatFlags & kAudioFormatFlagIsAlignedHigh > 0 ? "AlignedHigh" : "AlignedLow",
            mFormatFlags & kAudioFormatFlagIsNonInterleaved > 0 ? "NonInterleaved" : "Interleaved",
            mFormatFlags & kAudioFormatFlagIsNonMixable > 0 ? "NonMixable" : "Mixable",
        ].compactMap {$0}.joined(separator: ", ")
    }
}
