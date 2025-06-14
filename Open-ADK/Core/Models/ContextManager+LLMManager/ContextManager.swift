import SwiftSoup

class NewContextManager {
    
    init() {
        
    }
    
    func pullContextFromPage(for webView: WKWebView) {
        webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { result, error in
            if let html = result as? String {
                let dom = NewDOMTree(for: html)
                print(try? dom.rootElement?.element?.text())
            } else {
                print("Failed to Extract Content")
            }
        }
    }
}

