package se.lindskogen.hakkerneus.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

class HttpException(val code: Int) : Exception("The server responded with status $code.")

class NotFoundException(val id: Long) : Exception("Item $id could not be found.")

/** The only network primitive the clients need, so tests can serve fixtures. */
fun interface HttpTransport {
    suspend fun get(url: String): String
}

class OkHttpTransport(private val client: OkHttpClient = OkHttpClient()) : HttpTransport {
    override suspend fun get(url: String): String = withContext(Dispatchers.IO) {
        client.newCall(Request.Builder().url(url).build()).execute().use { response ->
            if (!response.isSuccessful) throw HttpException(response.code)
            response.body.string()
        }
    }
}
