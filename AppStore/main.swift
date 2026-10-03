// The App Store edition's entry point. The direct edition's,
// Sources/quoth/main.swift, is the same call (ADR-007).
MainActor.assumeIsolated { QuothApp.main() }
