package se.lindskogen.hakkerneus.html

object HtmlText {
    private val named = mapOf("amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'", "nbsp" to " ")

    /** Decodes the named entities HN emits plus all numeric (`&#39;`, `&#x27;`) entities. */
    fun decodeEntities(input: String): String {
        if ('&' !in input) return input
        val out = StringBuilder(input.length)
        var i = 0
        while (i < input.length) {
            val c = input[i]
            if (c == '&') {
                // Entities are short; don't scan arbitrarily far for a semicolon.
                val semicolon = input.indexOf(';', i).takeIf { it in (i + 1)..(i + 9) }
                val decoded = semicolon?.let { decode(input.substring(i + 1, it)) }
                if (semicolon != null && decoded != null) {
                    out.append(decoded)
                    i = semicolon + 1
                    continue
                }
            }
            out.append(c)
            i++
        }
        return out.toString()
    }

    private fun decode(name: String): String? {
        if (name.startsWith("#")) {
            val digits = name.drop(1)
            val value = if (digits.startsWith("x", ignoreCase = true)) digits.drop(1).toIntOrNull(16) else digits.toIntOrNull()
            return value?.takeIf { Character.isValidCodePoint(it) }?.let { String(Character.toChars(it)) }
        }
        return named[name]
    }
}
