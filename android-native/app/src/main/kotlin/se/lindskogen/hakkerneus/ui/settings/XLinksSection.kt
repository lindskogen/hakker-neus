package se.lindskogen.hakkerneus.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row as LayoutRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.data.NitterRedirect
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.theme.HN

/** Settings > X links: whether x.com links open through Nitter, and which instances back up xcancel.com. */
@Composable
fun XLinksSection() {
    val nitter = AppContainer.nitter
    var adding by remember { mutableStateOf(false) }
    Section("X links")
    LayoutRow(
        Modifier.fillMaxWidth().background(Color(0xFF26292E))
            .toggleable(value = nitter.enabled, role = Role.Switch) { nitter.updateEnabled(it) }
            .padding(horizontal = 20.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("Open via Nitter", style = HN.body, modifier = Modifier.weight(1f))
        Switch(checked = nitter.enabled, onCheckedChange = null)
    }
    Footer("Opens posts on x.com and twitter.com through Nitter, which shows them without an X account. Turn off to open them on X.")
    if (!nitter.enabled) return

    Section("Primary")
    LayoutRow(Modifier.fillMaxWidth().background(Color(0xFF26292E)).padding(horizontal = 20.dp, vertical = 14.dp)) {
        Text(NitterRedirect.PRIMARY, style = HN.body, modifier = Modifier.weight(1f))
        Text("Tried first", style = HN.body.copy(color = Color.White.copy(alpha = 0.5f)))
    }
    Section("Fallbacks")
    for (host in nitter.knownInstances) {
        val added = host !in NitterRedirect.suggestedFallbacks
        LayoutRow(
            Modifier.fillMaxWidth().background(Color(0xFF26292E)).clickable { nitter.toggleFallback(host) }
                .padding(start = 20.dp, end = if (added) 4.dp else 20.dp, top = if (added) 2.dp else 14.dp, bottom = if (added) 2.dp else 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(host, style = HN.body, modifier = Modifier.weight(1f))
            if (host in nitter.fallbacks) Text("✓", style = HN.body.copy(color = HN.accent, fontSize = 18.sp))
            if (added) IconButton(onClick = { nitter.removeInstance(host) }) {
                Icon(HnIcons.close, contentDescription = "Remove $host", tint = Color.White.copy(alpha = 0.5f))
            }
        }
    }
    Row("Add instance…", color = HN.accent) { adding = true }
    Footer("Tried in order when the one before is down; with none up, links open on X. Nitter instances come and go, so add one you trust if these stop working.")

    if (adding) {
        var text by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { adding = false },
            title = { Text("Add Nitter instance") },
            text = {
                OutlinedTextField(
                    value = text, onValueChange = { text = it }, singleLine = true,
                    placeholder = { Text("nitter.example.com") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                )
            },
            confirmButton = {
                TextButton(enabled = NitterRedirect.host(text) != null, onClick = {
                    NitterRedirect.host(text)?.let(nitter::addInstance)
                    adding = false
                }) { Text("Add") }
            },
            dismissButton = { TextButton(onClick = { adding = false }) { Text("Cancel") } },
        )
    }
}
