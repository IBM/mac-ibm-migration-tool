//
//  WebView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 07/10/2025.
//  © Copyright IBM Corp. 2023, 2025
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI
import WebKit
import Network

/// A SwiftUI view that embeds a `WKWebView` for displaying web content on macOS.
/// 
/// `WebView` uses `NSViewRepresentable` to bridge a `WKWebView` into SwiftUI. 
/// You can provide a URL to load, and optionally a closure to be notified when navigation finishes.
///
/// - Parameters:
///   - url: The URL to load in the web view.
///   - onNavigationFinished: An optional closure that is called when navigation finishes or fails. 
///     The closure receives a Boolean indicating success (`true`) or failure (`false`).
struct WebView: NSViewRepresentable {
    var url: URL
    var onNavigationFinished: ((Bool) -> Void)?
    
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "WebViewMonitorQueue")
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                DispatchQueue.main.async {
                    let request = URLRequest(url: url)
                    webView.load(request)
                }
                monitor.cancel()
            } else {
                DispatchQueue.main.async {
                    onNavigationFinished?(false)
                }
                monitor.cancel()
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onNavigationFinished?(true)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onNavigationFinished?(false)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let response = navigationResponse.response as? HTTPURLResponse {
                if !(200...299).contains(response.statusCode) {
                    parent.onNavigationFinished?(false)
                }
            }
            decisionHandler(.allow)
        }
    }
}
