StudioMemo
A professional spoken-word recording, songwriting, and AI stem separation app for iPhone and iPad. Built entirely in Swift with a modular, phase-driven architecture across 39 source files.

Features
Multi-clip recording — AVAudioEngine-backed capture with real-time level metering, pause/resume, and per-clip gain control
Waveform timeline — zoomable, scrollable multi-track editor with markers and a playhead transport
Transcript-linked editing — Apple Speech framework transcription with segment-level timestamps, confidence scores, and searchable text
AI stem separation — CoreML-ready engine separating audio into vocals, drums, bass, piano, and accompaniment (2, 4, or 5-stem modes)
Stem mixer — per-track volume and mute controls via a dedicated AVAudioEngine mixing graph
Export pipeline — per-clip or full mixdown export in M4A (AAC), WAV (24-bit), and CAF with optional normalization and metadata embedding
Crash recovery — orphan sweep on launch, file integrity checks, and atomic writes throughout
StoreKit 2 IAP — monthly/annual Pro subscriptions, one-time Stem Lab unlock, and consumable transcription credit packs
Architecture
StudioMemo/
├── App/
│   ├── StudioMemoApp.swift          # @main entry, UIKit appearance
│   ├── AppRouter.swift              # Tab navigation + permissions gate
│   ├── AppEnvironment.swift         # DI container, bootstrap sequence
│   └── AppTheme.swift               # Design tokens: colors, fonts, spacing, radii
│
├── Core/
│   ├── Audio/
│   │   ├── AudioSessionManager.swift    # AVAudioSession lifecycle + route/interruption publishers
│   │   ├── AudioEngineManager.swift     # AVAudioEngine graph, tap, metering, playback
│   │   ├── AudioFormatManager.swift     # Format construction, M4A/WAV conversion, duration
│   │   ├── AudioRouter.swift            # Input source selection + route change observation
│   │   └── AudioFileService.swift       # File I/O, waveform sampling, export dispatch
│   │
│   ├── AI/
│   │   ├── SpeechAnalyzerAdapter.swift  # SFSpeechRecognizer wrapper (file + live streaming)
│   │   ├── TranscriptJob.swift          # Observable async transcription job runner
│   │   ├── StemSeparationEngine.swift   # CoreML inference orchestrator + buffer I/O
│   │   ├── StemJob.swift                # Observable async stem separation job runner
│   │   └── SessionInsightsEngine.swift  # NLTagger-based auto-title, summary, tag extraction
│   │
│   ├── Persistence/
│   │   ├── FileStore.swift              # File system layout, atomic JSON read/write
│   │   ├── MetadataStore.swift          # Actor-isolated JSON persistence for all models
│   │   ├── ProjectRepository.swift      # @MainActor CRUD facade + @Published session list
│   │   └── RecoveryManager.swift        # Orphan sweep, integrity checks, temp cleanup
│   │
│   └── Utilities/
│       ├── AppError.swift               # Exhaustive typed error hierarchy (6 domains)
│       ├── Logger.swift                 # os.log structured logging (5 categories)
│       ├── Permissions.swift            # Mic + speech recognition async request wrappers
│       ├── AsyncState.swift             # Generic idle/loading/success/failure state enum
│       └── DateHelpers.swift            # TimeInterval → mm:ss / hh:mm:ss, relative dates
│
└── Features/
    ├── Home/                    # Hero record button, recent sessions, mode quick-start
    ├── Capture/                 # Record/pause/resume/stop, level meter, clip list
    ├── Timeline/                # Zoomable waveform editor, marker rail, transport bar
    ├── Session/                 # Session list (search/sort), detail view, editor sheet
    ├── Transcription/           # Segment list, search, word count, transcribe trigger
    ├── StemLab/                 # File import, job queue, multi-track stem mixer
    ├── Export/                  # Format picker, options, async mixdown, share sheet
    └── Settings/                # Audio hardware, behavior prefs, IAP, permissions gate
Build Phases
Phase	Scope	Status
1	App shell, permissions, audio capture, session save/load	✅ Complete
2	Waveform timeline, markers, playback transport	✅ Complete
3	Transcription jobs, transcript-linked editing, auto-title/summary	✅ Complete
4	Stem import, separation jobs, stem mixer, export pipeline	✅ Complete
5	Hardening, recovery, error states, StoreKit 2 IAP	✅ Complete
Data Models
Model	Key Fields
SessionModel	id, title, createdAt, updatedAt, notes, tags, mode, durationSeconds, clipCount
ClipModel	id, sessionId, fileURL, trackId, startTime, endTime, isMuted, gain
TranscriptSegmentModel	id, sessionId, clipId, text, startTime, endTime, confidence
MarkerModel	id, sessionId, label, timestamp, color
StemJobModel	id, sourceURL, status, mode, progress, outputURLs, createdAt
TranscriptJobModel	id, sessionId, clipId, status, locale, createdAt
All models are Codable, Sendable, and persisted as atomic JSON via FileStore.

Requirements
Requirement	Value
Platform	iOS 17.0+ / iPadOS 17.0+
Language	Swift 5.9+
Xcode	15.0+
Concurrency	Swift async/await + Actors throughout
Frameworks	AVFoundation, Speech, NaturalLanguage, CoreML, StoreKit 2, Accelerate
External dependencies	None
Setup
git clone https://github.com/your-org/StudioMemo.git
cd StudioMemo
open StudioMemo.xcodeproj
Select your target device, set your Team in Signing & Capabilities, and build. No package manager required.

Required Info.plist keys
<key>NSMicrophoneUsageDescription</key>
<string>StudioMemo needs microphone access to record audio.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>StudioMemo uses speech recognition to transcribe your recordings.</string>

<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
Concurrency model
AppEnvironment — @MainActor, owns all service references
MetadataStore — actor, serializes all disk I/O
AudioEngineManager — @MainActor, bridges AVAudioEngine tap callbacks via Task { @MainActor }
StemSeparationEngine — actor, isolates CoreML inference and buffer processing
SpeechAnalyzerAdapter — actor, isolates SFSpeechRecognizer task lifecycle
All exported types conform to Sendable
Error handling
All errors flow through AppError, a typed enum with six domain cases:

enum AppError: Error {
    case bootstrap(underlying: Error)
    case audio(AudioErrorCode)
    case persistence(PersistenceErrorCode)
    case transcription(TranscriptionErrorCode)
    case stem(StemErrorCode)
    case export(ExportErrorCode)
    case permissions(PermissionErrorCode)
}
Every async operation surfaces errors to @Published var error: AppError? on its ViewModel. No silent failures.

Stem separation (Phase 4 integration note)
StemSeparationEngine ships with an energy-split stub that produces correct-shaped output buffers for all stem tracks. To integrate a production model:

Add your .mlpackage to Resources/Models/
Replace the runSeparation(buffers:mode:) method body in StemSeparationEngine.swift with MLModel inference
Map model output tensors back to the existing [StemJobModel.StemTrack: AVAudioPCMBuffer] return type
The job runner, file writer, mixer engine, and UI are model-agnostic.

Launch criteria
 Recording survives app backgrounding and phone calls
 Transcript jobs complete reliably for clips up to 30 minutes
 Stem jobs process without memory pressure warnings on A14+
 Sessions recover correctly after force-quit mid-recording
 Exports pass AVFoundation validation for all three formats
 UI maintains 60 fps during timeline scroll and waveform zoom
 StoreKit 2 purchase and restore flow verified in sandbox
