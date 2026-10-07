package org.gestorherramientas.gestor_herramientas_quill_test

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

object ToolManagement {
    fun attach(activity: MainActivity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "gestor_herramientas/management")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "openFile" -> {
                            val file = File(call.argument<String>("path") ?: "").canonicalFile
                            val folder = File(activity.applicationInfo.dataDir, "app_flutter/tool_documents").canonicalFile
                            require(file.parentFile == folder && file.isFile) { "Archivo no disponible" }
                            val uri = Uri.Builder().scheme("content").authority(activity.packageName + ".documents")
                                .appendPath(file.name).build()
                            val mime = documentMime(file.name)
                            val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            activity.startActivity(intent)
                            result.success(null)
                        }
                        "openUrl" -> {
                            val uri = Uri.parse(call.argument<String>("url") ?: "")
                            require(uri.scheme in listOf("https", "http") && !uri.host.isNullOrEmpty())
                            activity.startActivity(Intent(Intent.ACTION_VIEW, uri))
                            result.success(null)
                        }
                        "reminders" -> {
                            val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                            ReminderReceiver.replace(activity, JSONArray(items.map { JSONObject(it) }))
                            if (call.argument<Boolean>("requestPermission") == true && Build.VERSION.SDK_INT >= 33 &&
                                activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                                activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 430)
                            }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: android.content.ActivityNotFoundException) {
                    result.error("no_viewer", "No hay una aplicación para abrir este documento. Puedes usar Compartir.", null)
                } catch (error: Exception) {
                    result.error("management", error.message ?: "No se pudo completar la acción", null)
                }
            }
    }
}

fun documentMime(name: String): String = MimeTypeMap.getSingleton()
    .getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase()) ?: "application/octet-stream"

class ToolDocumentProvider : ContentProvider() {
    override fun onCreate() = true
    private fun document(uri: Uri): File {
        val segments = uri.pathSegments
        require(segments.size == 1 && segments[0].isNotBlank())
        val folder = File(context!!.applicationInfo.dataDir, "app_flutter/tool_documents").canonicalFile
        val file = File(folder, segments[0]).canonicalFile
        require(file.parentFile == folder && file.isFile) { "Archivo no disponible" }
        return file
    }
    override fun getType(uri: Uri): String = documentMime(document(uri).name)
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        val file = document(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(columns)
        cursor.addRow(columns.map { when (it) {
            OpenableColumns.DISPLAY_NAME -> file.name
            OpenableColumns.SIZE -> file.length()
            else -> null
        } }.toTypedArray())
        return cursor
    }
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        require(mode == "r") { "Solo lectura" }
        return ParcelFileDescriptor.open(document(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val preferences = context.getSharedPreferences("tool_reminders", Context.MODE_PRIVATE)
        val items = JSONArray(preferences.getString("items", "[]"))
        if (intent.action in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) {
            schedule(context, items)
            return
        }
        val id = intent.getStringExtra("id") ?: return
        val item = (0 until items.length()).map { items.getJSONObject(it) }
            .firstOrNull { it.getString("id") == id } ?: return
        val version = item.getString("version")
        if (preferences.getString("delivered_$id", "") == version) return
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(
            "tools_pending", "Préstamos y mantenimiento", NotificationManager.IMPORTANCE_DEFAULT))
        val launch = Intent(context, StartupActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val tap = PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, "tools_pending") else Notification.Builder(context)
        manager.notify(id.hashCode(), builder.setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(item.getString("title")).setContentText(item.getString("text"))
            .setContentIntent(tap).setAutoCancel(true).build())
        preferences.edit().putString("delivered_$id", version).apply()
    }
    companion object {
        private fun pending(context: Context, id: String): PendingIntent {
            val intent = Intent(context, ReminderReceiver::class.java)
                .setData(Uri.parse("tool-reminder://pending/$id")).putExtra("id", id)
            return PendingIntent.getBroadcast(context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        fun replace(context: Context, items: JSONArray) {
            val preferences = context.getSharedPreferences("tool_reminders", Context.MODE_PRIVATE)
            val old = JSONArray(preferences.getString("items", "[]"))
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            for (i in 0 until old.length()) {
                val item = old.getJSONObject(i)
                val id = item.getString("id")
                alarm.cancel(pending(context, id))
                if ((0 until items.length()).none { items.getJSONObject(it).getString("id") == id }) {
                    notifications.cancel(id.hashCode())
                }
            }
            preferences.edit().putString("items", items.toString()).apply()
            schedule(context, items)
        }
        fun schedule(context: Context, items: JSONArray) {
            val preferences = context.getSharedPreferences("tool_reminders", Context.MODE_PRIVATE)
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                val id = item.getString("id")
                if (preferences.getString("delivered_$id", "") == item.getString("version")) continue
                val time = maxOf(item.getLong("time"), System.currentTimeMillis() + 10000L)
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, pending(context, id))
            }
        }
    }
}
