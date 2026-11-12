package se.lindskogen.hakkerneus.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.browser.customtabs.CustomTabColorSchemeParams
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.ui.graphics.toArgb
import android.net.Uri
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.ui.theme.HN

/** Opens a link in a Chrome Custom Tab, coloured like the app; X links go through Nitter. */
fun Context.openInBrowser(url: String) {
    val nitter = AppContainer.nitter
    if (nitter.redirects(url)) AppContainer.launch { openInCustomTab(nitter.resolve(url)) } else openInCustomTab(url)
}

private fun Context.openInCustomTab(url: String) {
    browserOpened.tryEmit(url)
    val colors = CustomTabColorSchemeParams.Builder().setToolbarColor(HN.backgroundDark.toArgb()).build()
    CustomTabsIntent.Builder()
        .setDefaultColorSchemeParams(colors)
        .setShowTitle(true)
        .build()
        .launchUrl(this, Uri.parse(url))
}

fun Context.share(url: String, title: String? = null) {
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, url)
        title?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
    }
    startActivity(Intent.createChooser(send, null))
}

fun Context.copyToClipboard(text: String, label: String = "Link") {
    getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText(label, text))
}

/** Opens an HN user's page in the app; provided by AppNavigation. */
val LocalOpenUser = androidx.compose.runtime.staticCompositionLocalOf<(String) -> Unit> { {} }
