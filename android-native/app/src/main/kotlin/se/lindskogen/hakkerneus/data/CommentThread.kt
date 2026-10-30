package se.lindskogen.hakkerneus.data

/**
 * Depth-first flattening, ported from `flattenComments` in the RN app. Comments without text
 * (deleted) are left out, but their replies are kept at the depth they'd have had.
 */
fun List<Comment>.flattened(depth: Int = 0): List<FlatComment> = flatMap { comment ->
    val replies = comment.children.flattened(depth + 1)
    if (comment.text.isNullOrEmpty()) replies else listOf(FlatComment(comment, depth)) + replies
}

/** The flattened comments of one item plus which ones the user has collapsed. */
data class CommentThread(val comments: List<FlatComment>, private val collapsedIds: Set<Long> = emptySet()) {
    /** Collapsed IDs that still exist (all of them while there are no comments yet). */
    val collapsed: Set<Long> =
        if (comments.isEmpty()) collapsedIds else collapsedIds intersect comments.mapTo(HashSet()) { it.id }

    /** Number of replies (at any depth) under each comment. */
    val replyCounts: Map<Long, Int> = buildMap {
        val open = ArrayDeque<FlatComment>()
        for (comment in comments) {
            while (open.isNotEmpty() && open.last().depth >= comment.depth) open.removeLast()
            for (ancestor in open) put(ancestor.id, (get(ancestor.id) ?: 0) + 1)
            open.addLast(comment)
        }
    }

    /** Comments to show: collapsed comments stay visible but their replies are hidden. */
    val visible: List<FlatComment>
        get() {
            val result = mutableListOf<FlatComment>()
            var hideDeeperThan: Int? = null
            for (comment in comments) {
                val limit = hideDeeperThan
                if (limit != null && comment.depth > limit) continue
                hideDeeperThan = null
                result += comment
                if (comment.id in collapsed) hideDeeperThan = comment.depth
            }
            return result
        }

    fun isCollapsed(id: Long) = id in collapsed

    fun toggled(id: Long) = copy(collapsedIds = if (id in collapsed) collapsed - id else collapsed + id)

    /** Expands every collapsed comment above [id], so it's visible. */
    fun expandingAncestors(id: Long): CommentThread {
        val ancestors = ArrayDeque<FlatComment>()
        for (comment in comments) {
            while (ancestors.isNotEmpty() && ancestors.last().depth >= comment.depth) ancestors.removeLast()
            if (comment.id == id) return copy(collapsedIds = collapsed - ancestors.map { it.id }.toSet())
            ancestors.addLast(comment)
        }
        return this
    }
}
