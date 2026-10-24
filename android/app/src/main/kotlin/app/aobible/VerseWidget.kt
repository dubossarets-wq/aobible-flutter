package app.aobible

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONArray

/**
 * Виджет «Стих дня» на главном экране. Стихи на 30 дней вперёд присылает приложение (Dart: features/plans/verse_widget.dart
 * через home_widget → ключи items и title); здесь берётся стих на сегодняшнюю дату (нет такого — последний из списка).
 * Нажатие открывает приложение. Система обновляет виджет раз в несколько часов (verse_widget_info.xml) —
 * стих меняется и без запуска приложения.
 */
class VerseWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views(context, widgetData))
    }

    private fun views(ctx: Context, data: SharedPreferences): RemoteViews {
        val v = RemoteViews(ctx.packageName, R.layout.widget_verse)
        var text = ctx.getString(R.string.widget_empty)
        var ref = ""
        val title = data.getString("title", "") ?: ""
        try {
            val items = JSONArray(data.getString("items", "[]"))
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            var pick = if (items.length() > 0) items.getJSONObject(0) else null
            for (i in 0 until items.length()) {
                val it = items.getJSONObject(i)
                if (it.optString("d") <= today) pick = it // список по датам — последний не позже сегодня
            }
            if (pick != null) {
                text = pick.optString("text", text)
                ref = pick.optString("ref", "")
            }
        } catch (_: Exception) {
            // нет данных — подсказка открыть приложение
        }
        v.setTextViewText(R.id.widget_title, if (title.isEmpty()) ctx.getString(R.string.widget_title) else title)
        v.setTextViewText(R.id.widget_text, text)
        v.setTextViewText(R.id.widget_ref, ref)
        val open = Intent(ctx, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pi = PendingIntent.getActivity(ctx, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        v.setOnClickPendingIntent(R.id.widget_root, pi)
        return v
    }
}
