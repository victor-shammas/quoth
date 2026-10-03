import QuothCore

// The direct edition's entry point. Everything lives in QuothCore; the App
// Store edition's entry point, AppStore/main.swift, is the same call.
MainActor.assumeIsolated { QuothApp.main() }
