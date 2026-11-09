package se.lindskogen.hakkerneus.ui

import se.lindskogen.hakkerneus.data.TopStoriesFeed

/** What the app is about: Hacker News, or lobste.rs ("lobster mode"). Remembered between launches (see AppContainer). */
enum class Site(val title: String) {
    HackerNews("Hacker News"),
    Lobsters("lobste.rs");

    val other: Site get() = if (this == HackerNews) Lobsters else HackerNews
}

/** Somewhere the reel on the corner button goes. Feeds switch in place; the rest open on top. */
enum class Place(val title: String, val feed: TopStoriesFeed.Source? = null) {
    Top("Top", TopStoriesFeed.Source.Top),
    New("New", TopStoriesFeed.Source.New),
    Hottest("Hottest", TopStoriesFeed.Source.LobstersHottest),
    Newest("Newest", TopStoriesFeed.Source.LobstersNewest),
    /** The one saved list, with both sites' stories and comments. */
    Saved("Saved"),
    Search("Search");

    companion object {
        fun of(feed: TopStoriesFeed.Source) = entries.first { it.feed == feed }
    }
}
