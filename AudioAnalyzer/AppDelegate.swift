//
//  AppDelegate.swift
//  AudioAnalyzer
//
//  Created by BAN Jun on R 3/01/14.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBAction func newDocument(_ sender: AnyObject) {
        NSWindowController(window: NSWindow(contentViewController: ViewController())).showWindow(nil)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        newDocument(self)
        return true
    }
}

