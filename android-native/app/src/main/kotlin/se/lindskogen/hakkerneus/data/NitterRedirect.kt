package se.lindskogen.hakkerneus.data

import android.content.SharedPreferences
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * Opens x.com and twitter.com links through Nitter, which shows posts without an X account, as on
 * iOS: xcancel.com first, then the user's fallbacks in order, skipping instances that are down
 * (they come and go, and get suspended). When none respond, links open on X.
 */
class NitterRedirect(private val settings: SharedPreferences) {
    companion object {
        const val PRIMARY = "xcancel.com"
        /** Offered as fallbacks. Checked 2026-11-04: most public instances shut down after X's
         * cease-and-desist letters; these answer, behind bot checks a browser passes. */
        val suggestedFallbacks = listOf("nitter.tiekoetter.com", "nitter.meowing.monster", "nitter.privacyredirect.com")
        private val xHosts = setOf("x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com")
        /** How long a check of the instances is trusted. */
        private const val CHECK_LIFETIME_MS = 10 * 60 * 1000L

        fun isXLink(url: String): Boolean = Uri.parse(url).host?.lowercase() in xHosts

        /** The host from what was typed: a bare host or a whole URL. */
        fun host(text: String): String? {
            val trimmed = text.trim().lowercase()
            val host = Uri.parse(if ("://" in trimmed) trimmed else "https://$trimmed").host ?: return null
            return host.takeIf { "." in it && it != PRIMARY }
        }
    }

    /** Whether X links go through Nitter. Compose state. */
    var enabled by mutableStateOf(settings.getBoolean("opensXLinksViaNitter", true))
        private set

    /** Instances tried after xcancel.com, in order. Compose state. */
    var fallbacks by mutableStateOf(settings.getString("nitterFallbacks", null)?.split(",")?.filter { it.isNotEmpty() } ?: suggestedFallbacks)
        private set

    /** Instances the user added, offered beside the suggested ones. Compose state. */
    var customInstances by mutableStateOf(settings.getString("customNitterInstances", null)?.split(",")?.filter { it.isNotEmpty() } ?: emptyList())
        private set

    /** Suggested and added instances, in the order fallbacks are tried. */
    val knownInstances: List<String> get() = (suggestedFallbacks + customInstances + fallbacks).distinct()

    private val client = OkHttpClient.Builder().callTimeout(3, TimeUnit.SECONDS).build()
    private var lastCheck: Pair<String?, Long>? = null
    private var checking: CompletableDeferred<String?>? = null

    fun redirects(url: String) = enabled && isXLink(url)

    /** [url] on the first instance that's up; [url] itself if it isn't redirected or none is up. */
    suspend fun resolve(url: String): String {
        if (!redirects(url)) return url
        val host = workingInstance() ?: return url
        return Uri.parse(url).buildUpon().scheme("https").encodedAuthority(host).build().toString()
    }

    fun updateEnabled(on: Boolean) {
        enabled = on
        settings.edit().putBoolean("opensXLinksViaNitter", on).apply()
        invalidate()
    }

    /** Turns [host] on or off as a fallback, keeping the listed order. */
    fun toggleFallback(host: String) {
        val chosen = fallbacks.toMutableSet().apply { if (!add(host)) remove(host) }
        saveFallbacks(chosen)
    }

    fun addInstance(host: String) {
        if (host !in knownInstances) {
            customInstances = customInstances + host
            settings.edit().putString("customNitterInstances", customInstances.joinToString(",")).apply()
        }
        saveFallbacks(fallbacks.toSet() + host)
    }

    fun removeInstance(host: String) {
        customInstances = customInstances - host
        settings.edit().putString("customNitterInstances", customInstances.joinToString(",")).apply()
        saveFallbacks(fallbacks.toSet() - host)
    }

    private fun saveFallbacks(chosen: Set<String>) {
        fallbacks = knownInstances.filter { it in chosen }
        settings.edit().putString("nitterFallbacks", fallbacks.joinToString(",")).apply()
        invalidate()
    }

    private fun invalidate() {
        lastCheck = null
        checking = null
    }

    /** Must be called on the main thread, like the rest of the app's state. */
    suspend fun workingInstance(): String? {
        lastCheck?.let { (host, at) -> if (System.currentTimeMillis() - at < CHECK_LIFETIME_MS) return host }
        checking?.let { return it.await() }
        val deferred = CompletableDeferred<String?>()
        checking = deferred
        val instances = listOf(PRIMARY) + fallbacks
        val host = withContext(Dispatchers.IO) { instances.firstOrNull { isUp(it) } }
        if (checking === deferred) {
            lastCheck = host to System.currentTimeMillis()
            checking = null
        }
        deferred.complete(host)
        return host
    }

    /** Up unless it doesn't answer or answers like a suspended, overloaded or missing site
     * (xcancel answers 451 while suspended). Bot checks (often 403) pass in a browser. */
    private fun isUp(host: String): Boolean = try {
        client.newCall(Request.Builder().url("https://$host/").head().build()).execute().use { response ->
            val status = response.code
            !(status == 404 || status == 429 || status == 451 || status >= 500)
        }
    } catch (e: Exception) {
        false
    }
}
