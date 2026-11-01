package se.lindskogen.hakkerneus.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import se.lindskogen.hakkerneus.ui.theme.HN

/** Text tabs across the full width (Stories / Comments on a user page, the order of search
 * results): the selected one white with an accent line under it that slides over when the tab
 * changes, the others dimmed. */
@Composable
fun TextTabs(titles: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val tabWidth = maxWidth / titles.size
        val indicatorOffset by animateDpAsState(
            tabWidth * selected,
            spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMediumLow),
            label = "indicator",
        )
        Row(Modifier.fillMaxWidth().selectableGroup()) {
            titles.forEachIndexed { index, title ->
                val isSelected = index == selected
                val color by animateColorAsState(Color.White.copy(alpha = if (isSelected) 1f else 0.4f), tween(250), label = "tab")
                Box(
                    Modifier
                        .weight(1f)
                        .heightIn(min = 44.dp)
                        .selectable(selected = isSelected, role = Role.Tab, onClick = { if (!isSelected) onSelect(index) }),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        title,
                        style = HN.body.copy(fontSize = 16.sp, fontWeight = FontWeight.Medium, color = color),
                        modifier = Modifier.padding(vertical = 10.dp),
                    )
                }
            }
        }
        Box(
            Modifier
                .align(Alignment.BottomStart)
                .offset(x = indicatorOffset)
                .width(tabWidth)
                .height(2.dp)
                .background(HN.accent, RoundedCornerShape(1.dp)),
        )
    }
}
