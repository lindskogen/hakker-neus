package se.lindskogen.hakkerneus.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.openInBrowser
import se.lindskogen.hakkerneus.ui.theme.HN

/** Username and password for news.ycombinator.com, with autofill hints. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SignInScreen(done: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var captcha by remember { mutableStateOf(false) }

    fun submit() {
        if (username.isBlank() || password.isEmpty()) {
            error = "Enter your username and password."
            return
        }
        busy = true
        error = null
        scope.launch {
            try {
                AppContainer.session.signIn(username.trim(), password)
                val then = AppContainer.afterSignIn
                AppContainer.afterSignIn = null
                done()
                then?.invoke()
            } catch (e: Exception) {
                error = e.message
                captcha = e is HnSession.Failure.Captcha
            } finally {
                busy = false
            }
        }
    }

    Scaffold(
        containerColor = HN.backgroundDark,
        topBar = {
            TopAppBar(
                title = { Text("Sign In") },
                navigationIcon = { IconButton(onClick = { AppContainer.afterSignIn = null; done() }) { Icon(HnIcons.close, contentDescription = "Cancel") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = HN.backgroundDark, titleContentColor = Color.White, navigationIconContentColor = Color.White),
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                "Sign in with your Hacker News account to vote and comment. Your password is sent to news.ycombinator.com and not stored.",
                style = HN.body.copy(fontSize = 14.sp, color = Color.White.copy(alpha = 0.6f)),
            )
            OutlinedTextField(
                value = username, onValueChange = { username = it }, label = { Text("Username") }, singleLine = true, enabled = !busy,
                keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, imeAction = ImeAction.Next),
                modifier = Modifier.fillMaxWidth().semantics { contentType = ContentType.Username },
            )
            OutlinedTextField(
                value = password, onValueChange = { password = it }, label = { Text("Password") }, singleLine = true, enabled = !busy,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { submit() }),
                modifier = Modifier.fillMaxWidth().semantics { contentType = ContentType.Password },
            )
            Button(
                onClick = ::submit, enabled = !busy, modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = HN.accent, contentColor = Color.White),
            ) { Text("Sign In") }
            if (busy) CircularProgressIndicator(color = Color.White)
            error?.let { Text(it, style = HN.body.copy(fontSize = 14.sp, color = Color(0xFFFF6B5E))) }
            // After a CAPTCHA, signing in once on the website usually clears it for the app too.
            if (captcha) TextButton(onClick = { context.openInBrowser("${HnSession.BASE}login") }) { Text("Sign in on the website") }
        }
    }
}
