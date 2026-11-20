import AuthenticationServices
import SwiftRs
import Tauri
import UIKit
import WebKit

struct RunArgs: Decodable {
  let url: String
  let scheme: String
}

// The sheet iOS gives a web sign-in. It shares Safari's cookies and passkeys,
// and hands back the URL the node redirects it to, so the ticket arrives here
// and not through a deep link into a relaunched app.
class Sheet: Plugin {
  // Held until the sheet calls back. A session nobody holds is released
  // before it opens, and then never calls back.
  private var session: ASWebAuthenticationSession?
  private let anchor = Anchor()

  // "the page should simply not zoom, not own it, the zoom is QNTX's to
  // manage, not the app, not the page, nothing for accesibility"
  //
  // The web view zooms nothing: not onto a field that takes the keyboard,
  // not under two fingers. A page that wants pinching reads the fingers
  // itself, from the touches it still gets.
  override func load(webview: WKWebView) {
    let scroll = webview.scrollView
    scroll.pinchGestureRecognizer?.isEnabled = false
    scroll.minimumZoomScale = 1
    scroll.maximumZoomScale = 1
    scroll.bouncesZoom = false
    withoutAccessoryBar(webview)
  }

  @objc public func run(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(RunArgs.self)
    guard let url = URL(string: args.url) else {
      invoke.reject("not a url: \(args.url)")
      return
    }
    DispatchQueue.main.async {
      let session = ASWebAuthenticationSession(url: url, callbackURLScheme: args.scheme) {
        cameBack, error in
        self.session = nil
        if let cameBack = cameBack {
          invoke.resolve(["url": cameBack.absoluteString])
          return
        }
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
          invoke.reject("cancelled")
          return
        }
        invoke.reject(error?.localizedDescription ?? "the sheet closed with no callback")
      }
      session.presentationContextProvider = self.anchor
      // Safari's session is the point: the person's accounts are already there.
      session.prefersEphemeralWebBrowserSession = false
      self.session = session
      if !session.start() {
        self.session = nil
        invoke.reject("the sheet did not open")
      }
    }
  }
}

// WKWebView puts a bar over the keyboard while a field on the page has it:
// ^ and ∨ to the previous and next field, ✓ to close the keyboard. A native
// field has none. No setting turns it off: the view the page is drawn in is
// asked for its `inputAccessoryView`, and here that view is given a class of
// its own that answers nil.
private func withoutAccessoryBar(_ webview: WKWebView) {
  guard let content = webview.scrollView.subviews.first(where: {
    NSStringFromClass(type(of: $0)).hasPrefix("WKContent")
  }) else { return }
  let original: AnyClass = type(of: content)
  let name = NSStringFromClass(original) + "WithoutAccessoryBar"
  if let made = NSClassFromString(name) {
    object_setClass(content, made)
    return
  }
  let selector = #selector(getter: UIResponder.inputAccessoryView)
  guard let method = class_getInstanceMethod(UIResponder.self, selector),
        let made = objc_allocateClassPair(original, name, 0) else { return }
  let none: @convention(block) (AnyObject) -> UIView? = { _ in nil }
  class_addMethod(made, selector, imp_implementationWithBlock(none), method_getTypeEncoding(method))
  objc_registerClassPair(made)
  object_setClass(content, made)
}

// Where the sheet is presented: the window the App is showing.
class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return windows.first { $0.isKeyWindow } ?? windows.first ?? ASPresentationAnchor()
  }
}

@_cdecl("init_sheet")
func initPlugin() -> Plugin {
  return Sheet()
}
