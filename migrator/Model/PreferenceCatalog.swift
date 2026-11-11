//
//  PreferenceCatalog.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 01/10/2026.
//  © Copyright IBM Corp. 2023, 2026
//  SPDX-License-Identifier: Apache2.0
//

import Foundation

/// Identifies a `CFPreferences` domain and the subset of its keys that belong to a `PreferenceCatalogItem`.
struct PreferenceDomain: Hashable, Sendable {
    
    /// Describes which keys of a domain's values should be kept.
    enum KeyFilter: Hashable, Sendable {
        /// Keep every key.
        case all
        /// Keep every key except the ones listed.
        case allExcept([String])
        /// Keep only the keys listed.
        case only([String])
        /// Keep keys that start with any of the given prefixes.
        case prefixes([String])
    }
    
    /// Key prefixes dropped from every domain because they only make sense on the Mac where they were captured
    /// (window positions, navigation panel state, split view layout).
    static let transientKeyPrefixes: [String] = ["NSWindow Frame",
                                                 "NSSplitView",
                                                 "NSNavPanel",
                                                 "NSNavLastRootDirectory",
                                                 "NSOSPLastRootDirectory"]
    
    /// The `CFPreferences` application ID, e.g. `"com.apple.dock"`. `nil` means the global domain
    /// (`kCFPreferencesAnyApplication`, i.e. `.GlobalPreferences.plist`).
    let applicationID: String?
    /// Whether this domain is host-specific (`kCFPreferencesCurrentHost`), used for settings tied to this Mac's hardware.
    let isByHost: Bool
    /// Which keys of the domain's values belong to the owning `PreferenceCatalogItem`.
    let keyFilter: KeyFilter
    
    init(applicationID: String?, isByHost: Bool = false, keyFilter: KeyFilter) {
        self.applicationID = applicationID
        self.isByHost = isByHost
        self.keyFilter = keyFilter
    }
    
    /// Applies `keyFilter` and the transient-key drop list to a dictionary of discovered values.
    /// - Parameter values: The raw values read from this domain.
    /// - Returns: Only the values that belong to this catalog item.
    func filter(_ values: [String: Any]) -> [String: Any] {
        let base: [String: Any]
        switch keyFilter {
        case .all:
            base = values
        case .allExcept(let excluded):
            base = values.filter { !excluded.contains($0.key) }
        case .only(let included):
            base = values.filter { included.contains($0.key) }
        case .prefixes(let prefixes):
            base = values.filter { key, _ in prefixes.contains { key.hasPrefix($0) } }
        }
        return base.filter { key, _ in !Self.transientKeyPrefixes.contains { key.hasPrefix($0) } }
    }
}

/// Describes one named, selectable group of macOS preferences, e.g. "Dock Preferences".
struct PreferenceCatalogItem: Sendable {
    /// Stable identifier used for logging, the migration report and catalog lookups.
    let id: String
    /// Localization key for the group's display name.
    let nameKey: String
    /// SF Symbol shown next to the group.
    let iconName: String
    /// Localization keys for the human-readable settings shown in the group's info popover.
    let settingDescriptionKeys: [String]
    /// The preference domains that make up this group.
    let domains: [PreferenceDomain]
}

/// The catalog of macOS preference groups the app knows how to migrate.
struct PreferenceCatalog {
    
    static let allItems: [PreferenceCatalogItem] = [
        PreferenceCatalogItem(id: "dock",
                              nameKey: "migration.preferences.dock.name",
                              iconName: "dock.rectangle",
                              settingDescriptionKeys: ["migration.preferences.dock.setting.position",
                                                       "migration.preferences.dock.setting.size",
                                                       "migration.preferences.dock.setting.autohide",
                                                       "migration.preferences.dock.setting.minimizeEffect",
                                                       "migration.preferences.dock.setting.recentApps",
                                                       "migration.preferences.dock.setting.pinnedItems"],
                              domains: [PreferenceDomain(applicationID: "com.apple.dock",
                                                         keyFilter: .allExcept(["wvous-tl-corner", "wvous-tr-corner", "wvous-bl-corner", "wvous-br-corner",
                                                                                "wvous-tl-modifier", "wvous-tr-modifier", "wvous-bl-modifier", "wvous-br-modifier",
                                                                                "mru-spaces", "expose-group-apps", "expose-animation-duration",
                                                                                "mod-count", "version", "loc", "trash-full", "lastShowIndicatorTime"]))]),
        PreferenceCatalogItem(id: "hotCorners",
                              nameKey: "migration.preferences.hotCorners.name",
                              iconName: "rectangle.3.group",
                              settingDescriptionKeys: ["migration.preferences.hotCorners.setting.action",
                                                       "migration.preferences.hotCorners.setting.modifier"],
                              domains: [PreferenceDomain(applicationID: "com.apple.dock",
                                                         keyFilter: .only(["wvous-tl-corner", "wvous-tr-corner", "wvous-bl-corner", "wvous-br-corner",
                                                                           "wvous-tl-modifier", "wvous-tr-modifier", "wvous-bl-modifier", "wvous-br-modifier"]))]),
        PreferenceCatalogItem(id: "missionControl",
                              nameKey: "migration.preferences.missionControl.name",
                              iconName: "square.stack.3d.up",
                              settingDescriptionKeys: ["migration.preferences.missionControl.setting.rearrangeSpaces",
                                                       "migration.preferences.missionControl.setting.groupByApp",
                                                       "migration.preferences.missionControl.setting.displaysHaveSeparateSpaces"],
                              domains: [PreferenceDomain(applicationID: "com.apple.dock",
                                                         keyFilter: .only(["mru-spaces", "expose-group-apps", "expose-animation-duration"])),
                                        PreferenceDomain(applicationID: "com.apple.spaces",
                                                         keyFilter: .only(["spans-displays"]))]),
        PreferenceCatalogItem(id: "desktopStageManager",
                              nameKey: "migration.preferences.desktopStageManager.name",
                              iconName: "macwindow.on.rectangle",
                              settingDescriptionKeys: ["migration.preferences.desktopStageManager.setting.stageManager",
                                                       "migration.preferences.desktopStageManager.setting.clickWallpaper",
                                                       "migration.preferences.desktopStageManager.setting.tiling"],
                              domains: [PreferenceDomain(applicationID: "com.apple.WindowManager", keyFilter: .all)]),
        PreferenceCatalogItem(id: "finder",
                              nameKey: "migration.preferences.finder.name",
                              iconName: "folder",
                              settingDescriptionKeys: ["migration.preferences.finder.setting.viewStyle",
                                                       "migration.preferences.finder.setting.bars",
                                                       "migration.preferences.finder.setting.newWindowTarget",
                                                       "migration.preferences.finder.setting.fileExtensions",
                                                       "migration.preferences.finder.setting.desktopItems",
                                                       "migration.preferences.finder.setting.searchScope"],
                              domains: [PreferenceDomain(applicationID: "com.apple.finder",
                                                         keyFilter: .allExcept(["FXRecentFolders", "RecentMoveAndCopyDestinations",
                                                                                "GoToField", "GoToFieldHistory",
                                                                                "FXDesktopVolumePositions", "FXConnectToLastURL"])),
                                        PreferenceDomain(applicationID: "com.apple.desktopservices",
                                                         keyFilter: .only(["DSDontWriteNetworkStores", "DSDontWriteUSBStores"]))]),
        PreferenceCatalogItem(id: "appearance",
                              nameKey: "migration.preferences.appearance.name",
                              iconName: "paintpalette",
                              settingDescriptionKeys: ["migration.preferences.appearance.setting.lightDarkAuto",
                                                       "migration.preferences.appearance.setting.accentColor",
                                                       "migration.preferences.appearance.setting.highlightColor",
                                                       "migration.preferences.appearance.setting.scrollBars",
                                                       "migration.preferences.appearance.setting.sidebarIconSize",
                                                       "migration.preferences.appearance.setting.windowBehavior"],
                              domains: [PreferenceDomain(applicationID: nil,
                                                         keyFilter: .only(["AppleInterfaceStyle", "AppleInterfaceStyleSwitchesAutomatically",
                                                                           "AppleAccentColor", "AppleHighlightColor", "AppleIconAppearanceTheme",
                                                                           "AppleShowScrollBars", "AppleScrollerPagingBehavior", "NSTableViewDefaultSizeMode",
                                                                           "AppleReduceDesktopTinting", "AppleActionOnDoubleClick", "AppleMiniaturizeOnDoubleClick",
                                                                           "NSCloseAlwaysConfirmsChanges", "NSQuitAlwaysKeepsWindows", "AppleWindowTabbingMode"]))]),
        PreferenceCatalogItem(id: "keyboard",
                              nameKey: "migration.preferences.keyboard.name",
                              iconName: "keyboard",
                              settingDescriptionKeys: ["migration.preferences.keyboard.setting.keyRepeat",
                                                       "migration.preferences.keyboard.setting.pressAndHold",
                                                       "migration.preferences.keyboard.setting.fnKey",
                                                       "migration.preferences.keyboard.setting.autocorrect",
                                                       "migration.preferences.keyboard.setting.inputSources"],
                              domains: [PreferenceDomain(applicationID: nil,
                                                         keyFilter: .only(["KeyRepeat", "InitialKeyRepeat", "ApplePressAndHoldEnabled", "AppleKeyboardUIMode",
                                                                           "com.apple.keyboard.fnState",
                                                                           "NSAutomaticSpellingCorrectionEnabled", "NSAutomaticCapitalizationEnabled",
                                                                           "NSAutomaticPeriodSubstitutionEnabled", "NSAutomaticQuoteSubstitutionEnabled",
                                                                           "NSAutomaticDashSubstitutionEnabled", "WebAutomaticSpellingCorrectionEnabled"])),
                                        PreferenceDomain(applicationID: "com.apple.HIToolbox",
                                                         keyFilter: .only(["AppleEnabledInputSources", "AppleSelectedInputSources", "AppleFnUsageType", "AppleCurrentKeyboardLayoutInputSourceID"]))]),
        PreferenceCatalogItem(id: "keyboardShortcuts",
                              nameKey: "migration.preferences.keyboardShortcuts.name",
                              iconName: "command",
                              settingDescriptionKeys: ["migration.preferences.keyboardShortcuts.setting.systemShortcuts",
                                                       "migration.preferences.keyboardShortcuts.setting.appShortcuts"],
                              domains: [PreferenceDomain(applicationID: "com.apple.symbolichotkeys",
                                                         keyFilter: .only(["AppleSymbolicHotKeys"])),
                                        PreferenceDomain(applicationID: nil,
                                                         keyFilter: .only(["NSUserKeyEquivalents"]))]),
        PreferenceCatalogItem(id: "trackpad",
                              nameKey: "migration.preferences.trackpad.name",
                              iconName: "hand.draw",
                              settingDescriptionKeys: ["migration.preferences.trackpad.setting.tapToClick",
                                                       "migration.preferences.trackpad.setting.trackingSpeed",
                                                       "migration.preferences.trackpad.setting.forceClick",
                                                       "migration.preferences.trackpad.setting.gestures",
                                                       "migration.preferences.trackpad.setting.naturalScrolling"],
                              domains: [PreferenceDomain(applicationID: "com.apple.AppleMultitouchTrackpad", keyFilter: .all),
                                        PreferenceDomain(applicationID: "com.apple.driver.AppleBluetoothMultitouch.trackpad", keyFilter: .all),
                                        PreferenceDomain(applicationID: nil,
                                                         keyFilter: .only(["com.apple.trackpad.scaling", "com.apple.trackpad.forceClick", "com.apple.swipescrolldirection"]))]),
        PreferenceCatalogItem(id: "mouse",
                              nameKey: "migration.preferences.mouse.name",
                              iconName: "computermouse",
                              settingDescriptionKeys: ["migration.preferences.mouse.setting.trackingSpeed",
                                                       "migration.preferences.mouse.setting.scrollingSpeed",
                                                       "migration.preferences.mouse.setting.secondaryClick",
                                                       "migration.preferences.mouse.setting.gestures",
                                                       "migration.preferences.mouse.setting.naturalScrolling"],
                              domains: [PreferenceDomain(applicationID: "com.apple.AppleMultitouchMouse", keyFilter: .all),
                                        PreferenceDomain(applicationID: "com.apple.driver.AppleBluetoothMultitouch.mouse", keyFilter: .all),
                                        PreferenceDomain(applicationID: nil,
                                                         keyFilter: .only(["com.apple.mouse.scaling", "com.apple.scrollwheel.scaling", "com.apple.swipescrolldirection"]))]),
        PreferenceCatalogItem(id: "languageRegion",
                              nameKey: "migration.preferences.languageRegion.name",
                              iconName: "globe",
                              settingDescriptionKeys: ["migration.preferences.languageRegion.setting.languages",
                                                       "migration.preferences.languageRegion.setting.region",
                                                       "migration.preferences.languageRegion.setting.units",
                                                       "migration.preferences.languageRegion.setting.firstWeekday",
                                                       "migration.preferences.languageRegion.setting.dateTimeFormats"],
                              domains: [PreferenceDomain(applicationID: nil,
                                                         keyFilter: .only(["AppleLanguages", "AppleLocale", "AppleMeasurementUnits", "AppleMetricUnits",
                                                                           "AppleTemperatureUnit", "AppleFirstWeekday", "AppleICUForce24HourTime",
                                                                           "AppleICUDateFormatStrings", "AppleICUNumberSymbols"]))]),
        PreferenceCatalogItem(id: "menuBarControlCenter",
                              nameKey: "migration.preferences.menuBarControlCenter.name",
                              iconName: "menubar.rectangle",
                              settingDescriptionKeys: ["migration.preferences.menuBarControlCenter.setting.menuBarItems",
                                                       "migration.preferences.menuBarControlCenter.setting.autoHide",
                                                       "migration.preferences.menuBarControlCenter.setting.clockFormat"],
                              domains: [PreferenceDomain(applicationID: "com.apple.controlcenter", keyFilter: .all),
                                        PreferenceDomain(applicationID: nil,
                                                         keyFilter: .only(["_HIHideMenuBar", "AppleMenuBarVisibleInFullscreen"])),
                                        PreferenceDomain(applicationID: "com.apple.menuextra.clock", keyFilter: .all)]),
        PreferenceCatalogItem(id: "soundEffects",
                              nameKey: "migration.preferences.soundEffects.name",
                              iconName: "speaker.wave.2",
                              settingDescriptionKeys: ["migration.preferences.soundEffects.setting.alertSound",
                                                       "migration.preferences.soundEffects.setting.uiSounds",
                                                       "migration.preferences.soundEffects.setting.volumeFeedback"],
                              domains: [PreferenceDomain(applicationID: nil,
                                                         keyFilter: .only(["com.apple.sound.beep.sound", "com.apple.sound.beep.volume",
                                                                           "com.apple.sound.beep.feedback", "com.apple.sound.uiaudio.enabled"]))]),
        PreferenceCatalogItem(id: "screenshots",
                              nameKey: "migration.preferences.screenshots.name",
                              iconName: "camera.viewfinder",
                              settingDescriptionKeys: ["migration.preferences.screenshots.setting.saveLocation",
                                                       "migration.preferences.screenshots.setting.fileFormat",
                                                       "migration.preferences.screenshots.setting.windowShadow",
                                                       "migration.preferences.screenshots.setting.floatingThumbnail"],
                              domains: [PreferenceDomain(applicationID: "com.apple.screencapture", keyFilter: .all)]),
        PreferenceCatalogItem(id: "screenSaver",
                              nameKey: "migration.preferences.screenSaver.name",
                              iconName: "display",
                              settingDescriptionKeys: ["migration.preferences.screenSaver.setting.chosenSaver",
                                                       "migration.preferences.screenSaver.setting.startDelay",
                                                       "migration.preferences.screenSaver.setting.clock"],
                              domains: [PreferenceDomain(applicationID: "com.apple.screensaver",
                                                         isByHost: true,
                                                         keyFilter: .only(["idleTime", "moduleDict", "showClock"]))]),
        PreferenceCatalogItem(id: "accessibility",
                              nameKey: "migration.preferences.accessibility.name",
                              iconName: "accessibility",
                              settingDescriptionKeys: ["migration.preferences.accessibility.setting.motionTransparency",
                                                       "migration.preferences.accessibility.setting.contrast",
                                                       "migration.preferences.accessibility.setting.buttonShapes",
                                                       "migration.preferences.accessibility.setting.pointerSize",
                                                       "migration.preferences.accessibility.setting.zoom"],
                              domains: [PreferenceDomain(applicationID: "com.apple.universalaccess",
                                                         keyFilter: .only(["reduceMotion", "reduceTransparency", "increaseContrast", "differentiateWithoutColor",
                                                                           "showToolbarButtonShapes", "mouseDriverCursorSize",
                                                                           "closeViewScrollWheelToggle", "closeViewHotkeysEnabled"]))]),
        PreferenceCatalogItem(id: "terminal",
                              nameKey: "migration.preferences.terminal.name",
                              iconName: "terminal",
                              settingDescriptionKeys: ["migration.preferences.terminal.setting.profiles",
                                                       "migration.preferences.terminal.setting.defaultStartupProfile",
                                                       "migration.preferences.terminal.setting.shellBehavior"],
                              domains: [PreferenceDomain(applicationID: "com.apple.Terminal", keyFilter: .all)])
    ]
}

