# IBM Data Shift - Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Repository                        │
│                   (Source Code & Releases)                      │
└──────────────────────────────┬──────────────────────────────────┘
                               │ Download / Updates
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                         macOS Device                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │          IBM Data Shift (SwiftUI Native App)            │    │
│  │─────────────────────────────────────────────────────────│    │
│  │  - Runs entirely locally on macOS                       │    │
│  │  - No external servers required                         │    │
│  │  - Open-source executable                               │    │
│  │  - Peer-to-peer network architecture                    │    │
│  └──────────────┬──────────────┬──────────────┬────────────┘    │
│                 │              │              │                 │
│        ┌────────▼────┐  ┌──────▼──────┐  ┌───▼────────┐         │
│        │   System    │  │   Network   │  │    User    │         │
│        │    APIs     │  │  Services   │  │   Input    │         │
│        └─────────────┘  └─────────────┘  └────────────┘         │
│                 │              │              │                 │
│  ┌──────────────▼──────────────▼──────────────▼─────────────┐   │
│  │                                                          │   │
│  │                  Application Layer                       │   │
│  │                                                          │   │
│  │  ┌─────────────────────────────────────────────────────┐ │   │
│  │  │              MigratorApp (SwiftUI)                  │ │   │
│  │  │  - App lifecycle management                         │ │   │
│  │  │  - Window configuration                             │ │   │
│  │  │  - Menu commands                                    │ │   │
│  │  └──────────────────────┬──────────────────────────────┘ │   │
│  │                         │                                │   │
│  │  ┌──────────────────────▼──────────────────────────────┐ │   │
│  │  │              MainView (SwiftUI)                     │ │   │
│  │  │  - Page navigation controller                       │ │   │
│  │  │  - Migration workflow orchestration                 │ │   │
│  │  └──────────────────────┬──────────────────────────────┘ │   │
│  │                         │                                │   │
│  │  ┌──────────────────────▼──────────────────────────────┐ │   │
│  │  │                  AppContext                         │ │   │
│  │  │  - Configuration management                         │ │   │
│  │  │  - UserDefaults integration                         │ │   │
│  │  │  - MDM profile settings                             │ │   │
│  │  │  - Customizable constants                           │ │   │
│  │  └─────────────────────────────────────────────────────┘ │   │
│  │                                                          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                                                         │    │
│  │                  Controller Layer                       │    │
│  │                                                         │    │
│  │  ┌───────────────────────────────────────────────────┐  │    │
│  │  │         MigrationController (Singleton)           │  │    │
│  │  │  - Central migration orchestration                │  │    │
│  │  │  - State management (discovery → completion)      │  │    │
│  │  │  - Operating mode (server/browser)                │  │    │
│  │  │  - Progress tracking & reporting                  │  │    │
│  │  └─────┬──────────────────┬──────────────────┬───────┘  │    │
│  │        │                  │                  │          │    │
│  │  ┌─────▼──────┐  ┌────────▼────────┐  ┌─────▼────────┐  │    │
│  │  │  Network   │  │   Network       │  │   Network    │  │    │
│  │  │   Server   │  │   Browser       │  │  Connection  │  │    │
│  │  │            │  │                 │  │              │  │    │
│  │  │ - Listener │  │ - Discovery     │  │ - Data       │  │    │
│  │  │ - Bonjour  │  │ - Bonjour       │  │   transfer   │  │    │
│  │  │   service  │  │   browsing      │  │ - Framing    │  │    │
│  │  │ - Passcode │  │ - Peer-to-peer  │  │ - Protocol   │  │    │
│  │  │   auth     │  │   discovery     │  │   handling   │  │    │
│  │  └────────────┘  └─────────────────┘  └──────────────┘  │    │
│  │                                                         │    │
│  │  ┌───────────────────────────────────────────────────┐  │    │
│  │  │           Security & Encryption Layer             │  │    │
│  │  │                                                   │  │    │
│  │  │  TLS 1.2+ with Pre-Shared Key (PSK)               │  │    │
│  │  │  ├─ Passcode-derived symmetric key (CryptoKit)    │  │    │
│  │  │  ├─ HMAC-SHA384 authentication                    │  │    │
│  │  │  ├─ TLS_PSK_WITH_AES_256_GCM_SHA384 cipher        │  │    │
│  │  │  └─ Build-unique PSK identity                     │  │    │
│  │  │                                                   │  │    │
│  │  │  All data transfer encrypted end-to-end           │  │    │
│  │  │  No certificates or PKI required                  │  │    │
│  │  └───────────────────────────────────────────────────┘  │    │
│  │                                                         │    │
│  │  ┌───────────────────────────────────────────────────┐  │    │
│  │  │         Other Controllers                         │  │    │
│  │  │  - ArchitectureDetector                           │  │    │
│  │  │  - DeviceManagementHelper                         │  │    │
│  │  │  - JamfReconManager                               │  │    │
│  │  │  - MigrationReportController                      │  │    │
│  │  └───────────────────────────────────────────────────┘  │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                                                         │    │
│  │                    Model Layer                          │    │
│  │                                                         │    │
│  │  ┌───────────────────────────────────────────────────┐  │    │
│  │  │              Core Models                          │  │    │
│  │  │  - MigrationItem                                  │  │    │
│  │  │  - MigrationOption                                │  │    │
│  │  │  - MigratorFile                                   │  │    │
│  │  │  - DiscoveredApplication                          │  │    │
│  │  │  - MigratorPage                                   │  │    │
│  │  └───────────────────────────────────────────────────┘  │    │
│  │                                                         │    │
│  │  ┌───────────────────────────────────────────────────┐  │    │
│  │  │           Network Protocol Models                 │  │    │
│  │  │  - MigratorNetworkProtocol                        │  │    │
│  │  │  - MigratorMessageType                            │  │    │
│  │  │  - DeviceInfoMessage                              │  │    │
│  │  │  - FileMessage                                    │  │    │
│  │  │  - DefaultsMessage                                │  │    │
│  │  │  - SymbolicLinkMessage                            │  │    │
│  │  └───────────────────────────────────────────────────┘  │    │
│  │                                                         │    │
│  │  ┌───────────────────────────────────────────────────┐  │    │
│  │  │         Device Management Models                  │  │    │
│  │  │  - ManagedEnvironment                             │  │    │
│  │  │  - DeviceManagementState                          │  │    │
│  │  └───────────────────────────────────────────────────┘  │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                                                         │    │
│  │                     View Layer                          │    │
│  │                                                         │    │
│  │  ┌───────────────────────────────────────────────────┐  │    │
│  │  │            Migration Workflow Views               │  │    │
│  │  │  - WelcomeView                                    │  │    │
│  │  │  - BrowserView (discover source device)           │  │    │
│  │  │  - ServerView (wait for connection)               │  │    │
│  │  │  - CodeVerificationView                           │  │    │
│  │  │  - MigrationSetupView                             │  │    │
│  │  │  - RecapView                                      │  │    │
│  │  │  - MigrationView                                  │  │    │
│  │  │  - AppleIDView                                    │  │    │
│  │  │  - JamfReconView                                  │  │    │
│  │  │  - RebootView                                     │  │    │
│  │  │  - FinalView                                      │  │    │
│  │  └───────────────────────────────────────────────────┘  │    │
│  │                                                         │    │
│  │  ┌───────────────────────────────────────────────────┐  │    │
│  │  │              Common UI Components                 │  │    │
│  │  │  - CardButton                                     │  │    │
│  │  │  - CustomAlertView                                │  │    │
│  │  │  - MigratorFileView                               │  │    │
│  │  │  - DeviceListRow                                  │  │    │
│  │  │  - ScrollingTextView                              │  │    │
│  │  └───────────────────────────────────────────────────┘  │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                                                         │    │
│  │              macOS System Integration                   │    │
│  │                                                         │    │
│  │  ┌───────────────────────────────────────────────────┐  │    │
│  │  │            macOS Frameworks                       │  │    │
│  │  │  - Foundation (file operations)                   │  │    │
│  │  │  - Network (Bonjour, peer-to-peer)                │  │    │
│  │  │  - AppKit (system integration)                    │  │    │
│  │  │  - SwiftUI (UI framework)                         │  │    │
│  │  │  - Combine (reactive programming)                 │  │    │
│  │  └───────────────────────────────────────────────────┘  │    │
│  │                                                         │    │
│  │  ┌───────────────────────────────────────────────────┐  │    │
│  │  │           System Services                         │  │    │
│  │  │  - FileManager (file system access)               │  │    │
│  │  │  - UserDefaults (preferences)                     │  │    │
│  │  │  - Bonjour/mDNS (service discovery)               │  │    │
│  │  │  - Network.framework (peer connections)           │  │    │
│  │  └───────────────────────────────────────────────────┘  │    │
│  │                                                         │    │
│  │  ┌───────────────────────────────────────────────────┐  │    │
│  │  │        Optional MDM Integration                   │  │    │
│  │  │  - Jamf Pro (inventory updates)                   │  │    │
│  │  │  - Configuration profiles                         │  │    │
│  │  │  - Managed preferences                            │  │    │
│  │  └───────────────────────────────────────────────────┘  │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

                               ║
                               ║ Encrypted Peer-to-Peer Network
                               ║ (Bonjour Discovery + TLS 1.2+ PSK)
                               ║
┌──────────────────────────────▼───────────────────────────────────┐
│                    Second macOS Device                           │
│              (Source or Destination Device)                      │
│                                                                  │
│  - Same IBM Data Shift app running in opposite mode              │
│  - Direct peer-to-peer connection via local network              │
│  - TLS-encrypted data transfer (AES-256-GCM)                     │
│  - Passcode-authenticated connection                             │
│  - No internet or external servers required                      │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```