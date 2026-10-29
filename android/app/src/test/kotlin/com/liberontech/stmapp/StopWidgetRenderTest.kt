package com.liberontech.stmapp

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// The stop widgets as a launcher draws them: TimbreStopWidget fills
// RemoteViews, Android inflates them (a view RemoteViews does not allow
// fails here, as "Problem loading widget" on the phone). Each test saves a
// picture to build/widget-previews/ at the root of the repository, with
// stops 574 and 3140 from test/fixtures. Run from android/:
// ./gradlew :app:testDebugUnitTest
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class StopWidgetRenderTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val min = 60_000L

    private fun bus(line: String, dest: String, clock: String, inMin: Int, acc: Boolean = false) =
        """{"line":"$line","dest":"$dest","clock":"$clock","dueMs":${System.currentTimeMillis() + inMin * min},"acc":$acc}"""

    private fun board(vararg buses: String, failedAgoMin: Int? = null) =
        """{"checkedAtMs":${System.currentTimeMillis() - 2 * min}""" +
            (failedAgoMin?.let { ""","failedAtMs":${System.currentTimeMillis() - it * min}""" } ?: "") +
            ""","arrivals":[${buses.joinToString(",")}]}"""

    private fun save(vararg entries: Pair<String, String>) {
        val edit = HomeWidgetPlugin.getData(context).edit().clear()
        entries.forEach { (k, v) -> edit.putString(k, v) }
        edit.commit()
    }

    @Before
    fun twoSavedStops() = save(
        "stops_saved" to """[{"id":574,"name":"SAN JOSE y ANDES"},""" +
            """{"id":3140,"name":"AV RAMON ANADOR y TIBURCIO GOMEZ"}]""",
        "stop_board_574" to board(
            bus("121", "PUNTA CARRETAS", "20:14", 1, acc = true),
            bus("538", "BUCEO", "20:16", 3),
            bus("144", "CEMENTERIO DEL NORTE", "20:17", 4),
            bus("116", "POCITOS", "20:19", 6)),
        "stop_board_3140" to board(
            bus("145", "BV ARTIGAS Y BV ESPAÑA", "20:18", 5, acc = true),
            bus("494", "DELTA DEL TIGRE (POR COMPEN)", "20:23", 10),
            bus("143", "CIUDADELA", "20:31", 18)),
    )

    @Test
    fun proximo() {
        val view = render(TimbreProximoWidget::class.java, R.layout.widget_stop_small, 170, 170, "proximo")
        val texts = texts(view)
        assertTrue(texts.toString(), "SAN JOSE y ANDES" in texts)
        assertTrue("~20:14" in texts)
        assertTrue(texts.any { it.startsWith("538 ~20:16 · 144") })
        assertTrue(texts.any { it.startsWith("Datos de las ") })
    }

    @Test
    fun parada() {
        val view = render(TimbreParadaWidget::class.java, R.layout.widget_stop_medium, 364, 170, "parada")
        val texts = texts(view)
        assertTrue(texts.toString(), "SAN JOSE y ANDES · 574" in texts)
        assertEquals(listOf("121", "538", "144"), texts.filter { it in setOf("121", "538", "144", "116") })
        assertTrue(texts.any { it.endsWith(" · horas estimadas") })
    }

    @Test
    fun misParadas() {
        val view = render(TimbreMisParadasWidget::class.java, R.layout.widget_stop_large, 364, 382, "mis-paradas")
        val texts = texts(view)
        assertTrue(texts.toString(), "AV RAMON ANADOR y TIBURCIO GOMEZ · 3140" in texts)
        assertTrue("CIUDADELA" in texts)
        assertTrue("Mi STM" in texts && "Recarga" in texts)
    }

    @Test
    fun noSavedStops() {
        save("stops_saved" to "[]")
        val view = render(TimbreParadaWidget::class.java, R.layout.widget_stop_medium, 364, 170, "sin-paradas")
        assertTrue(texts(view).contains("Agregá una parada en Mis paradas para verla acá."))
    }

    @Test
    fun noBusAndFailed() {
        save(
            "stops_saved" to """[{"id":4018,"name":"AV 18 DE JULIO y CONVENCION"}]""",
            "stop_board_4018" to board(failedAgoMin = 1),
        )
        val view = render(TimbreParadaWidget::class.java, R.layout.widget_stop_medium, 364, 170, "sin-omnibus-sin-conexion")
        val texts = texts(view)
        assertTrue(texts.toString(), "Sin próximos ómnibus en esta parada" in texts)
        assertTrue(texts.any { it.startsWith("No se pudo actualizar. Datos de las ") })
    }

    @Test
    fun aBusThatPassedIsGone() {
        save(
            "stops_saved" to """[{"id":574,"name":"SAN JOSE y ANDES"}]""",
            "stop_board_574" to board(
                bus("117", "PUNTA CARRETAS", "20:10", -2),
                bus("121", "PUNTA CARRETAS", "20:14", 1)),
        )
        val view = render(TimbreProximoWidget::class.java, R.layout.widget_stop_small, 170, 170, "paso-uno")
        val texts = texts(view)
        assertTrue(texts.toString(), "121" in texts)
        assertTrue("117" !in texts)
    }

    /** Places the widget, lets its provider fill it and draws it at w × h dp. */
    private fun render(kind: Class<out AppWidgetProvider>, layout: Int, wDp: Int, hDp: Int, name: String): View {
        val manager = shadowOf(AppWidgetManager.getInstance(context))
        val id = manager.createWidget(kind, layout)
        val view = manager.getViewFor(id)
        val density = context.resources.displayMetrics.density
        val w = (wDp * density).toInt()
        val h = (hDp * density).toInt()
        view.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY))
        view.layout(0, 0, w, h)
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        // A dark wallpaper behind the rounded board
        Canvas(bitmap).apply { drawColor(0xFF1B1F2A.toInt()); view.draw(this) }
        // Tests run in android/app; build/ at the root is Flutter's, ignored
        val dir = File("../../build/widget-previews").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        return view
    }

    /** The visible texts, in order. */
    private fun texts(view: View): List<String> {
        val out = mutableListOf<String>()
        fun walk(v: View) {
            if (v.visibility != View.VISIBLE) return
            if (v is TextView && v.text.isNotEmpty()) out += v.text.toString()
            if (v is ViewGroup) (0 until v.childCount).forEach { walk(v.getChildAt(it)) }
        }
        walk(view)
        return out
    }
}
