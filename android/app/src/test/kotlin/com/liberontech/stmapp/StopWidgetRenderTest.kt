package com.liberontech.stmapp

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.work.WorkManager
import androidx.work.Configuration
import androidx.test.core.app.ApplicationProvider
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
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
    fun twoSavedStops() {
        try {
            WorkManager.getInstance(context)
        } catch (_: IllegalStateException) {
            // Robolectric does not run AndroidX Startup providers.
            WorkManager.initialize(context, Configuration.Builder().build())
        }
        save(
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
    }

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
        assertTrue(texts.any { it.startsWith("Últimos datos\n") })
    }

    @Test
    fun aBusThatPassedStaysInTheLastSuccessfulSnapshot() {
        save(
            "stops_saved" to """[{"id":574,"name":"SAN JOSE y ANDES"}]""",
            "stop_board_574" to board(
                bus("117", "PUNTA CARRETAS", "20:10", -2),
                bus("121", "PUNTA CARRETAS", "20:14", 1)),
        )
        val view = render(TimbreProximoWidget::class.java, R.layout.widget_stop_small, 170, 170, "paso-uno")
        val texts = texts(view)
        assertTrue(texts.toString(), texts.any { "121" in it })
        assertTrue(texts.toString(), "117" in texts)
    }

    @Test
    fun yesterdayWithNoConnectionStillShowsRowsAndARefreshButton() {
        val yesterday = System.currentTimeMillis() - 24 * 60 * min
        save(
            "stops_saved" to """[{"id":574,"name":"BUENOS AIRES y GUAYAQUI"}]""",
            "stop_board_574" to """{"checkedAtMs":$yesterday,"failedAtMs":${System.currentTimeMillis()},"arrivals":[{"line":"121","dest":"POCITOS","clock":"10:47","dueMs":$yesterday,"acc":false}]}""",
        )
        for ((kind, layout, width, height, name) in listOf(
            RenderCase(TimbreProximoWidget::class.java, R.layout.widget_stop_small, 176, 221, "retained-proximo"),
            RenderCase(TimbreParadaWidget::class.java, R.layout.widget_stop_medium, 364, 170, "retained-parada"),
            RenderCase(TimbreMisParadasWidget::class.java, R.layout.widget_stop_large, 364, 382, "retained-mis-paradas"),
            RenderCase(TimbreAnchoWidget::class.java, R.layout.widget_stop_wide, 352, 221, "retained-ancho"),
            RenderCase(TimbreFlipWidget::class.java, R.layout.widget_stop_cover, 352, 339, "retained-flip5"),
        )) {
            val view = render(kind, layout, width, height, name)
            val text = texts(view)
            assertTrue(text.toString(), "121" in text)
            assertTrue(text.toString(), "~10:47" in text)
            assertTrue(text.any { it.startsWith("Últimos datos\n") })
            assertTrue(view.findViewById<View>(R.id.w_refresh).hasOnClickListeners())
            assertEquals(View.GONE, view.findViewById<View>(R.id.w_footer_icon).visibility)
        }
    }

    private data class RenderCase(val kind: Class<out AppWidgetProvider>, val layout: Int,
        val width: Int, val height: Int, val name: String)

    @Test
    fun longStopNamesWrapInFullAndLeaveTheRefreshButtonVisible() {
        val name = "AV GRAL JOSE GARIBALDI y BV JOSE BATLLE Y ORDONEZ"
        save(
            "stops_saved" to """[{"id":574,"name":"$name"}]""",
            "stop_board_574" to board(bus("121", "POCITOS", "11:09", 1)),
        )
        for ((kind, layout, width, height, file) in listOf(
            RenderCase(TimbreProximoWidget::class.java, R.layout.widget_stop_small, 176, 221, "full-name-proximo"),
            RenderCase(TimbreParadaWidget::class.java, R.layout.widget_stop_medium, 364, 170, "full-name-parada"),
            RenderCase(TimbreMisParadasWidget::class.java, R.layout.widget_stop_large, 364, 382, "full-name-mis-paradas"),
        )) {
            val view = render(kind, layout, width, height, file)
            val nameId = if (kind == TimbreMisParadasWidget::class.java) R.id.w_stop_name_1 else R.id.w_stop_name
            val title = view.findViewById<TextView>(nameId)
            assertTrue(title.text.toString(), title.text.startsWith(name))
            assertTrue("name should wrap", title.lineCount > 1)
            for (line in 0 until title.lineCount) assertEquals(0, title.layout.getEllipsisCount(line))
            assertEquals(title.text.length, title.layout.getLineEnd(title.lineCount - 1))
            val refresh = view.findViewById<View>(R.id.w_refresh)
            val position = refresh.at(view)
            assertTrue("refresh clipped", position[1] + refresh.height <= view.height)
        }
    }

    @Test
    fun wideKeepsTwoRowsAndShowsTheSameSnapshot() {
        val view = render(TimbreAnchoWidget::class.java, R.layout.widget_stop_wide,
            352, 221, "proximo-ancho")
        val text = texts(view)
        assertTrue(text.toString(), "SAN JOSE y ANDES" in text)
        assertTrue("121" in text && "~20:14" in text)
        assertTrue(text.any { it.startsWith("538 ~20:16 · 144") })
        assertTrue(view.findViewById<View>(R.id.w_line).width >= 54 * context.resources.displayMetrics.density)
        assertTrue(view.findViewById<View>(R.id.w_dest).width >= 50 * context.resources.displayMetrics.density)
        assertButtonInside(view)
    }

    @Test
    fun coverFitsSixRowsAndTheFullStopNameInBothCoverOrientations() {
        val name = "AV GRAL JOSE GARIBALDI y BV JOSE BATLLE Y ORDONEZ"
        save(
            "stops_saved" to """[{"id":574,"name":"$name"}]""",
            "stop_board_574" to board(*listOf("121", "538", "144", "116", "145", "494")
                .mapIndexed { i, line -> bus(line, "PUNTA CARRETAS", "20:${14 + i}", i + 1) }.toTypedArray()),
        )
        for ((w, h) in listOf(352 to 339, 339 to 352)) {
            val view = render(TimbreFlipWidget::class.java, R.layout.widget_stop_cover,
                w, h, "flip5-${w}x$h")
            val text = texts(view)
            assertTrue(text.toString(), text.any { it.startsWith(name) })
            assertEquals(6, text.count { it in setOf("121", "538", "144", "116", "145", "494") })
            val title = view.findViewById<TextView>(R.id.w_stop_name)
            for (line in 0 until title.lineCount) assertEquals(0, title.layout.getEllipsisCount(line))
            val footer = view.findViewById<View>(R.id.w_footer)
            val at = footer.at(view)
            assertTrue("footer clipped", at[1] + footer.height <= view.height - 24 * context.resources.displayMetrics.density)
            assertButtonInside(view)
        }
    }

    @Test
    fun coverIsRegisteredForTheSamsungSubScreenPicker() {
        val component = android.content.ComponentName(context, TimbreFlipWidget::class.java)
        val info = context.packageManager.getReceiverInfo(component, android.content.pm.PackageManager.GET_META_DATA)
        assertEquals("Timbre · Flip5", info.loadLabel(context.packageManager).toString())
        val samsung = info.loadXmlMetaData(context.packageManager, "com.samsung.android.appwidget.provider")
        assertTrue("missing Samsung metadata", samsung != null)
        samsung!!.use { parser ->
            while (parser.eventType != org.xmlpull.v1.XmlPullParser.START_TAG) parser.next()
            assertEquals("samsung-appwidget-provider", parser.name)
            assertEquals("sub_screen", parser.getAttributeValue(null, "display"))
        }
        val standard = info.loadXmlMetaData(context.packageManager, "android.appwidget.provider")!!
        standard.use { parser ->
            while (parser.eventType != org.xmlpull.v1.XmlPullParser.START_TAG) parser.next()
            assertEquals(android.appwidget.AppWidgetProviderInfo.WIDGET_CATEGORY_KEYGUARD,
                parser.getAttributeIntValue("http://schemas.android.com/apk/res/android", "widgetCategory", 0))
        }
    }

    private fun assertButtonInside(view: View) {
        val refresh = view.findViewById<View>(R.id.w_refresh)
        val at = refresh.at(view)
        assertTrue("refresh clipped horizontally", at[0] >= 0 && at[0] + refresh.width <= view.width)
        assertTrue("refresh clipped vertically", at[1] >= 0 && at[1] + refresh.height <= view.height)
        assertTrue(refresh.hasOnClickListeners())
    }

    /** Where this view is inside [root], whose window may not start at 0, 0. */
    private fun View.at(root: View): IntArray {
        val mine = IntArray(2); getLocationInWindow(mine)
        val its = IntArray(2); root.getLocationInWindow(its)
        return intArrayOf(mine[0] - its[0], mine[1] - its[1])
    }

    /** Places the widget, lets its provider fill it and draws it at w × h dp. */
    private fun render(kind: Class<out AppWidgetProvider>, layout: Int, wDp: Int, hDp: Int, name: String): View {
        val manager = shadowOf(AppWidgetManager.getInstance(context))
        val id = manager.createWidget(kind, layout)
        val view = manager.getViewFor(id)
        // In a window, as on a home screen: a TextClock shows the time only
        // once attached
        Robolectric.buildActivity(Activity::class.java).setup().get()
            .setContentView(view, ViewGroup.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT))
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
