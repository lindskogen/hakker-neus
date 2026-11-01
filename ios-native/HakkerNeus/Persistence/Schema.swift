import Foundation

/// The app database's tables, as an ordered list of migrations.
/// `PRAGMA user_version` records how many have run; only append to this list.
enum Schema {
    static let migrations = [
        // 1: Saved stories.
        """
        CREATE TABLE IF NOT EXISTS saved_stories (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            author TEXT,
            url TEXT,
            text TEXT,
            score INTEGER NOT NULL,
            comment_count INTEGER NOT NULL,
            posted_at REAL NOT NULL,
            saved_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS saved_stories_saved_at ON saved_stories (saved_at DESC);
        """,
        // 2: Read state. seen_comment_count is null until the comments have been opened.
        """
        CREATE TABLE IF NOT EXISTS visited_stories (
            id INTEGER PRIMARY KEY,
            opened_at REAL NOT NULL,
            seen_comment_count INTEGER
        );
        """,
        // 3: Offline copies of comment threads, as StoryWithComments JSON.
        """
        CREATE TABLE IF NOT EXISTS item_cache (
            id INTEGER PRIMARY KEY,
            json TEXT NOT NULL,
            fetched_at REAL NOT NULL
        );
        """,
        // 4: Saved comments, with the story they're on.
        """
        CREATE TABLE IF NOT EXISTS saved_comments (
            id INTEGER PRIMARY KEY,
            story_id INTEGER,
            story_title TEXT,
            author TEXT,
            text TEXT NOT NULL,
            posted_at REAL NOT NULL,
            saved_at REAL NOT NULL
        );
        """,
    ]

    /// Runs any migrations the database hasn't had yet. Safe to call repeatedly.
    static func migrate(_ database: Database) throws {
        var version = database.userVersion
        while version < migrations.count {
            try database.transaction {
                try database.execute(migrations[version])
                try database.setUserVersion(version + 1)
            }
            version += 1
        }
    }
}
