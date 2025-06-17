// Shortcuts.swift
import SwiftUI

enum Shortcuts {
    static let newTab = KeyboardShortcut("t", modifiers: [.command])
    static let goBack = KeyboardShortcut(.leftArrow, modifiers: [.command])
    static let goBackAlt = KeyboardShortcut("[", modifiers: [.command])
    static let goForward = KeyboardShortcut(.rightArrow, modifiers: [.command])
    static let goForwardAlt = KeyboardShortcut("]", modifiers: [.command])
}
