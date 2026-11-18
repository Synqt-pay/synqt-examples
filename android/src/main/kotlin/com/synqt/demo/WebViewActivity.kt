package com.synqt.demo

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.Toast

/**
 * Shows the Payment Web App (or a direct-API GET redirect) in-app. The returnUrl goes back to
 * MainActivity, and payment app deep links (upi:, intent:, bank apps) open outside the WebView.
 */
class WebViewActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WebView.setWebContentsDebuggingEnabled(true) // test app: inspect the page via chrome://inspect
        val webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    val uri = request.url
                    when {
                        uri.toString().startsWith(RETURN_URL) -> startActivity(
                            Intent(this@WebViewActivity, MainActivity::class.java).setData(uri)
                                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                        )
                        uri.scheme == "http" || uri.scheme == "https" -> return false
                        else -> openExternally(uri.toString())
                    }
                    return true
                }

                // Path only: query strings carry the token.
                override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse) {
                    Log.w("SynqtDemo", "HTTP ${errorResponse.statusCode} ${request.method} ${request.url.host}${request.url.path}")
                }
            }
            loadUrl(requireNotNull(intent.dataString))
        }
        setContentView(FrameLayout(this).apply { fitsSystemWindows = true; addView(webView) })
    }

    private fun openExternally(url: String) {
        val target = if (url.startsWith("intent:")) {
            // The page controls this intent, so only allow what a browser would.
            Intent.parseUri(url, Intent.URI_INTENT_SCHEME).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
                component = null
                selector = null
            }
        } else {
            Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))
        }
        try {
            startActivity(target)
        } catch (error: ActivityNotFoundException) {
            Toast.makeText(this, "No app installed for this payment link", Toast.LENGTH_LONG).show()
        }
    }
}
