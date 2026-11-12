package se.lindskogen.hakkerneus.ui

import se.lindskogen.hakkerneus.data.TopStoriesFeed

/** What the app is about: Hacker News, or lobste.rs ("lobster mode"). Remembered between launches (see AppContainer). */
enum class Site(val title: String) {
    HackerNews("Hacker News"),
    Lobsters("lobste.rs");

    val other: Site get() = if (this == HackerNews) Lobsters else HackerNews
}

/**
 * A top-level place, picked in the sidebar. Each replaces the one showing and keeps its own
 * state. Going to one of [site]'s makes the app about that site; Saved has both sites' stories.
 */
enum class Place(val title: String, val site: Site?, val feed: TopStoriesFeed.Source? = null) {
    Top("Top", Site.HackerNews, TopStoriesFeed.Source.Top),
    New("New", Site.HackerNews, TopStoriesFeed.Source.New),
    /** Search is HN's (Algolia). */
    Search("Search", Site.HackerNews),
    Hottest("Hottest", Site.Lobsters, TopStoriesFeed.Source.LobstersHottest),
    Newest("Newest", Site.Lobsters, TopStoriesFeed.Source.LobstersNewest),
    /** Your own HN page (your stories and comments), or a way to sign in. */
    Profile("Profile", null),
    /** The one saved list, with both sites' stories and comments. */
    Saved("Saved", null);

    companion object {
        /** Where the app starts for [site], and where back goes from the other places. */
        fun home(site: Site) = if (site == Site.HackerNews) Top else Hottest
    }
}
