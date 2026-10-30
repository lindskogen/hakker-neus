package se.lindskogen.hakkerneus.account

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.data.Comment
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.theme.HN

/** Writing a comment or reply, with HN's formatting rules. Leaving keeps the draft. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ComposeScreen(parentId: Long, storyId: Long, context: String, done: () -> Unit) {
    val appContext = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf(AppContainer.drafts[parentId] ?: "") }
    var busy by remember { mutableStateOf(false) }
    val isReply = parentId != storyId

    fun saveDraft() {
        if (text.isBlank()) AppContainer.drafts.remove(parentId) else AppContainer.drafts[parentId] = text
    }

    fun post() {
        busy = true
        scope.launch {
            try {
                val session = AppContainer.session
                val newId = session.postComment(parentId, storyId, text)
                AppContainer.drafts.remove(parentId)
                val comment = Comment(
                    // Until Algolia catches up, a local stand-in; negative so it can't clash with HN IDs.
                    id = newId ?: -System.currentTimeMillis(),
                    author = session.username.value,
                    text = HnFormatting.html(text),
                    time = System.currentTimeMillis() / 1000,
                )
                AppContainer.localReplies.value = AppContainer.localReplies.value + AppContainer.LocalReply(storyId, parentId, comment)
                done()
            } catch (e: Exception) {
                saveDraft()
                if (e is HnSession.Failure.SessionExpired) AppContainer.session.signOut()
                Toast.makeText(appContext, e.message ?: "Couldn't post.", Toast.LENGTH_LONG).show()
            } finally {
                busy = false
            }
        }
    }

    Scaffold(
        containerColor = HN.backgroundDark,
        topBar = {
            TopAppBar(
                title = { Text(if (isReply) "Reply" else "Comment") },
                navigationIcon = { IconButton(onClick = { saveDraft(); done() }) { Icon(HnIcons.close, contentDescription = "Cancel") } },
                actions = {
                    if (busy) CircularProgressIndicator(color = Color.White, modifier = Modifier.padding(end = 16.dp).size(24.dp))
                    else TextButton(onClick = ::post, enabled = text.isNotBlank()) { Text("Post") }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = HN.backgroundDark, titleContentColor = Color.White, navigationIconContentColor = Color.White),
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).imePadding().padding(HN.padding), verticalArrangement = Arrangement.spacedBy(HN.padding)) {
            Text(context, style = HN.body.copy(fontSize = 14.sp, color = Color.White.copy(alpha = 0.6f)), maxLines = 3)
            Text("Blank line for a new paragraph · *italic* · indent two spaces for code", style = HN.body.copy(fontSize = 12.sp, color = Color.White.copy(alpha = 0.4f)))
            OutlinedTextField(
                value = text, onValueChange = { text = it }, enabled = !busy,
                modifier = Modifier.fillMaxWidth().weight(1f),
                textStyle = HN.body,
            )
        }
    }
}
