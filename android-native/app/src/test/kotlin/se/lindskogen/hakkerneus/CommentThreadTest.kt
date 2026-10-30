package se.lindskogen.hakkerneus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import se.lindskogen.hakkerneus.data.Comment
import se.lindskogen.hakkerneus.data.CommentThread
import se.lindskogen.hakkerneus.data.flattened

class CommentThreadTest {
    private fun c(id: Long, text: String? = "text", vararg children: Comment) = Comment(id, "user$id", text, 0, children.toList())

    // 1 ├ 2 │ └ 3 └ 4; 5
    private val tree = listOf(c(1, "t", c(2, "t", c(3)), c(4)), c(5))

    @Test
    fun flattensDepthFirstAndKeepsRepliesOfDeletedComments() {
        assertEquals(listOf(1L, 2, 3, 4, 5), tree.flattened().map { it.id })
        assertEquals(listOf(0, 1, 2, 1, 0), tree.flattened().map { it.depth })
        val deleted = listOf(c(1, null, c(2, "t", c(3))))
        assertEquals(listOf(2L, 3), deleted.flattened().map { it.id })
        assertEquals(listOf(1, 2), deleted.flattened().map { it.depth })
    }

    @Test
    fun collapsingHidesReplies() {
        var thread = CommentThread(tree.flattened())
        assertEquals(3, thread.replyCounts[1L])
        thread = thread.toggled(2)
        assertEquals(listOf(1L, 2, 4, 5), thread.visible.map { it.id })
        thread = thread.toggled(1)
        assertEquals(listOf(1L, 5), thread.visible.map { it.id })
        thread = thread.toggled(1)
        assertEquals(listOf(1L, 2, 4, 5), thread.visible.map { it.id })
    }

    @Test
    fun expandingAncestorsRevealsANestedComment() {
        val thread = CommentThread(tree.flattened()).toggled(1).toggled(2).toggled(5).expandingAncestors(3)
        assertEquals(listOf(1L, 2, 3, 4, 5), thread.visible.map { it.id })
        assertTrue(thread.isCollapsed(5))
    }
}
