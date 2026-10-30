package se.lindskogen.hakkerneus.account

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import se.lindskogen.hakkerneus.html.HtmlText

/**
 * The signed-in Hacker News session, as on iOS. HN has no write API, so signing in posts its
 * login form and keeps the `user` cookie it sets; votes and comments send that cookie.
 */
class HnSession(context: Context) {
    sealed class Failure(message: String) : Exception(message) {
        class BadLogin : Failure("Wrong username or password.")
        class Captcha : Failure("Hacker News wants to check you're human. Sign in on the website, then try again here.")
        class SessionExpired : Failure("Your Hacker News session has expired. Sign in again.")
        class NoVoteLink : Failure("Hacker News doesn't allow voting on this right now.")
        class CannotReply : Failure("Hacker News doesn't allow replying here.")
        class Rejected(message: String) : Failure(message)
        class Unexpected : Failure("Hacker News didn't respond as expected. Try again later.")
    }

    companion object {
        const val BASE = "https://news.ycombinator.com/"
    }

    private val vault = CookieVault(context)
    private val prefs = context.getSharedPreferences("session", Context.MODE_PRIVATE)
    // Redirects are where the login cookie and the "it worked" signal are, so don't follow them.
    private val http = OkHttpClient.Builder().followRedirects(false).followSslRedirects(false).build()

    private var cookie: String? = vault.load()
    private val _username = MutableStateFlow(cookie?.substringBefore('&'))
    /** The signed-in username, read from the cookie (`username&token`). */
    val username: StateFlow<String?> = _username

    private val _upvoted = MutableStateFlow(prefs.getStringSet("upvoted", emptySet())!!.mapNotNull { it.toLongOrNull() }.toSet())
    /** Stories the signed-in user has upvoted, as far as the app knows. */
    val upvoted: StateFlow<Set<Long>> = _upvoted
    /** Votes cast since a story's score was loaded, which that score doesn't include yet. */
    private val uncounted = mutableSetOf<Long>()

    val isSignedIn get() = cookie != null

    suspend fun signIn(username: String, password: String) {
        val response = send(
            Request.Builder().url("${BASE}login").post(FormBody.Builder().add("acct", username).add("pw", password).add("goto", "news").build()).build(),
            authorized = false,
        )
        // Success: a redirect that sets the `user` cookie. Failure: the login page again, with 200.
        val value = response.headers("Set-Cookie").firstNotNullOfOrNull { header ->
            header.substringBefore(';').takeIf { it.startsWith("user=") }?.removePrefix("user=")?.takeIf { it.isNotEmpty() }
        }
        if (value != null) {
            setCookie(value)
            return
        }
        val page = response.body.lowercase()
        throw when {
            "recaptcha" in page || "validation required" in page -> Failure.Captcha()
            "bad login" in page -> Failure.BadLogin()
            else -> Failure.Unexpected()
        }
    }

    fun signOut() {
        _upvoted.value = emptySet()
        uncounted.clear()
        prefs.edit().remove("upvoted").apply()
        setCookie(null)
    }

    private fun setCookie(value: String?) {
        cookie = value
        vault.save(value)
        _username.value = value?.substringBefore('&')
    }

    // MARK: Voting

    fun displayedScore(id: Long, score: Int) = score + if (id in uncounted) 1 else 0

    /** Records a vote locally, for the optimistic UI and rollback. */
    fun setLocalVote(id: Long, upvoted: Boolean, counted: Boolean = false) {
        _upvoted.value = if (upvoted) _upvoted.value + id else _upvoted.value - id
        if (upvoted && !counted) uncounted += id else uncounted -= id
        prefs.edit().putStringSet("upvoted", _upvoted.value.map { it.toString() }.toSet()).apply()
    }

    /** Whether the user has upvoted an item, from its HN page. */
    suspend fun isUpvotedOnHn(id: Long): Boolean {
        val page = itemPage(id)
        return voteLink(id, "un", page) != null ||
            Regex("id='up_$id'[^>]*nosee|nosee[^>]*id='up_$id'").containsMatchIn(page)
    }

    /** Upvotes, or undoes an upvote, with the per-session link on the item's page. */
    suspend fun vote(id: Long, up: Boolean) {
        val path = voteLink(id, if (up) "up" else "un", itemPage(id)) ?: throw Failure.NoVoteLink()
        val response = send(Request.Builder().url(BASE.toHttpUrl().resolve(path)!!).build())
        // Success redirects back to the item; an expired session redirects to the login page.
        if (response.header("Location")?.contains("login") == true) throw Failure.SessionExpired()
        if (response.code !in 300..399) throw Failure.Unexpected()
    }

    // MARK: Commenting

    /** Posts a comment on a story (parent == story) or a reply. Returns the new ID if HN reveals it. */
    suspend fun postComment(parent: Long, story: Long, text: String): Long? {
        val page = if (parent == story) itemPage(story) else fetchPage("${BASE}reply?id=$parent&goto=item%3Fid%3D$story")
        val hmac = Regex("""name=["']hmac["'][^>]*value=["']([^"']+)["']""").find(page)?.groupValues?.get(1)
            ?: throw if ("name=\"acct\"" in page) Failure.SessionExpired() else Failure.CannotReply()
        val response = send(
            Request.Builder().url("${BASE}comment").post(
                FormBody.Builder().add("parent", parent.toString()).add("goto", "item?id=$story").add("hmac", hmac).add("text", text).build(),
            ).build(),
        )
        if (response.code in 300..399) {
            val location = response.header("Location").orEmpty()
            if ("login" in location) throw Failure.SessionExpired()
            return Regex("#(\\d+)").find(location)?.groupValues?.get(1)?.toLongOrNull()
        }
        throw Failure.Rejected(rejectionMessage(response.body))
    }

    private fun rejectionMessage(page: String): String {
        val text = HtmlText.decodeEntities(page.replace(Regex("<[^>]+>"), " ")).split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        val known = listOf("You're posting too fast", "Please confirm", "too long", "Please try again")
        known.firstNotNullOfOrNull { phrase -> text.indexOf(phrase, ignoreCase = true).takeIf { it >= 0 } }?.let { return text.substring(it).take(200) }
        return text.ifEmpty { "Hacker News didn't accept the comment." }.take(200)
    }

    // MARK: Requests

    private class Page(val code: Int, val headers: okhttp3.Headers, val body: String) {
        fun header(name: String) = headers[name]
        fun headers(name: String) = headers.values(name)
    }

    private suspend fun itemPage(id: Long) = fetchPage("${BASE}item?id=$id")

    private suspend fun fetchPage(url: String): String {
        val response = send(Request.Builder().url(url).build())
        if (response.code in 300..399 && response.header("Location")?.contains("login") == true) throw Failure.SessionExpired()
        return response.body
    }

    private suspend fun send(request: Request, authorized: Boolean = true): Page = withContext(Dispatchers.IO) {
        val withCookie = if (authorized && cookie != null) request.newBuilder().header("Cookie", "user=$cookie").build() else request
        http.newCall(withCookie).execute().use { r: Response -> Page(r.code, r.headers, r.body.string()) }
    }

    /** The `vote?id=…&how=…&auth=…` link for an item; pages fetched without a session have none. */
    private fun voteLink(id: Long, how: String, page: String): String? =
        Regex("href='(vote\\?id=$id&amp;how=$how&amp;auth=[^']+)'").find(page)?.groupValues?.get(1)?.let(HtmlText::decodeEntities)
}
