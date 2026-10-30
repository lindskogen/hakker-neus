package se.lindskogen.hakkerneus.persistence

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * The app database: the same tables as the iOS app's `Schema`, as an ordered list of
 * migrations. The database version is how many have run; only append to the list.
 */
class Database(context: Context) : SQLiteOpenHelper(context, "hakkerneus.db", null, MIGRATIONS.size) {
    companion object {
        val MIGRATIONS = listOf(
            // 1: Saved stories.
            listOf(
                """
                CREATE TABLE IF NOT EXISTS saved_stories (
                    id INTEGER PRIMARY KEY, title TEXT NOT NULL, author TEXT, url TEXT, text TEXT,
                    score INTEGER NOT NULL, comment_count INTEGER NOT NULL,
                    posted_at REAL NOT NULL, saved_at REAL NOT NULL
                )
                """,
                "CREATE INDEX IF NOT EXISTS saved_stories_saved_at ON saved_stories (saved_at DESC)",
            ),
            // 2: Read state. seen_comment_count is null until the comments have been opened.
            listOf("CREATE TABLE IF NOT EXISTS visited_stories (id INTEGER PRIMARY KEY, opened_at REAL NOT NULL, seen_comment_count INTEGER)"),
            // 3: Offline copies of comment threads, as StoryWithComments JSON.
            listOf("CREATE TABLE IF NOT EXISTS item_cache (id INTEGER PRIMARY KEY, json TEXT NOT NULL, fetched_at REAL NOT NULL)"),
        )
    }

    override fun onCreate(db: SQLiteDatabase) = migrate(db, from = 0)

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = migrate(db, from = oldVersion)

    private fun migrate(db: SQLiteDatabase, from: Int) {
        for (statements in MIGRATIONS.drop(from)) statements.forEach { db.execSQL(it.trimIndent()) }
    }
}
