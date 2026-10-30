package se.lindskogen.hakkerneus.ui.settings

import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.persistence.BookmarksCsv
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.theme.HN

/** Settings, opened from the profile page's gear. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(back: () -> Unit, account: @Composable () -> Unit) {
    val context = LocalContext.current
    val entries by AppContainer.saved.entries.collectAsState()
    var result by remember { mutableStateOf<Pair<String, String>?>(null) }

    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        result = runCatching {
            val text = context.contentResolver.openInputStream(uri)!!.bufferedReader().use { it.readText() }
            val read = BookmarksCsv.read(text)
            val (added, already) = AppContainer.saved.merge(read.entries)
            val lines = buildList {
                add("Imported $added ${if (added == 1) "story" else "stories"}.")
                if (already > 0) add("$already already saved.")
                if (read.skipped > 0) add("Skipped ${read.skipped} unreadable ${if (read.skipped == 1) "row" else "rows"}.")
            }
            "Import Finished" to lines.joinToString(" ")
        }.getOrElse { "Couldn't Import" to (it.message ?: "The file couldn't be read.") }
    }
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        runCatching {
            context.contentResolver.openOutputStream(uri)!!.bufferedWriter().use { it.write(BookmarksCsv.write(AppContainer.saved.entries.value)) }
        }.onSuccess { Toast.makeText(context, "Exported ${entries.size} stories", Toast.LENGTH_SHORT).show() }
            .onFailure { result = "Couldn't Export" to (it.message ?: "") }
    }

    Scaffold(
        containerColor = HN.backgroundDark,
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = { IconButton(onClick = back) { Icon(HnIcons.close, contentDescription = "Close") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = HN.backgroundDark, titleContentColor = Color.White, navigationIconContentColor = Color.White),
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            account()
            Section("Saved stories")
            Row("Import from CSV…") { importer.launch(arrayOf("text/*", "application/csv", "application/octet-stream")) }
            Row("Export to CSV…") { exporter.launch("hakkerneus_bookmarks.csv") }
            Footer("${entries.size} saved. Uses the same CSV format as hacker-feed's bookmarks export.")
        }
    }

    result?.let { (title, message) ->
        AlertDialog(
            onDismissRequest = { result = null },
            confirmButton = { TextButton(onClick = { result = null }) { Text("OK") } },
            title = { Text(title) },
            text = { Text(message) },
        )
    }
}

@Composable
fun Section(title: String) {
    Text(title.uppercase(), style = HN.body.copy(fontSize = 13.sp, color = Color.White.copy(alpha = 0.5f)), modifier = Modifier.padding(start = 20.dp, top = 24.dp, bottom = 8.dp))
}

@Composable
fun Row(title: String, color: Color = Color.White, onClick: () -> Unit) {
    Text(
        title,
        style = HN.body.copy(color = color),
        modifier = Modifier.fillMaxWidth().background(Color(0xFF26292E)).clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = 14.dp),
    )
}

@Composable
fun Footer(text: String) {
    Text(text, style = HN.body.copy(fontSize = 13.sp, color = Color.White.copy(alpha = 0.5f)), modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
}
