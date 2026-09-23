package com.nova.nova_ai

import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ControlPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.nova.nova_ai/control")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val svc = JarvisAccessibilityService.instance

        when (call.method) {

            "isServiceEnabled" ->
                result.success(JarvisAccessibilityService.isEnabled())
            
            "is_service_enabled" ->
                result.success(mapOf("enabled" to JarvisAccessibilityService.isEnabled()))

            "openAccessibilitySettings" -> {
                context.startActivity(
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
                result.success(true)
            }

            // ═══ MESSAGES ═══

            /** Recent incoming messages, newest first. */
            "recent_messages" -> {
                val limit = call.argument<Int>("limit") ?: 15
                val msgs = NovaNotificationService.recent(limit).map {
                    mapOf("app" to it.pkg, "from" to it.sender, "text" to it.text,
                          "time" to it.time, "can_reply" to it.canReply)
                }
                result.success(mapOf("messages" to msgs,
                                     "listener_enabled" to NovaNotificationService.isEnabled()))
            }

            /** Reply straight from the notification — no app is opened. */
            "reply_message" -> {
                val who = call.argument<String>("who") ?: ""
                val text = call.argument<String>("text")
                    ?: return result.error("MISSING", "text required", null)
                if (!NovaNotificationService.isEnabled()) {
                    result.success(mapOf("status" to "listener_off"))
                    return
                }
                val sender = NovaNotificationService.instance?.reply(who, text)
                result.success(mapOf(
                    "status" to if (sender != null) "sent" else "no_conversation",
                    "to" to sender))
            }

            /** Look a name up in Contacts — avoids opening the contacts app. */
            "find_contact" -> {
                val name = call.argument<String>("name") ?: ""
                result.success(mapOf("matches" to Contacts.find(context, name)))
            }

            /** Open the chat with the text already filled in (and send it). */
            "message_app_send" -> {
                val app = call.argument<String>("app") ?: "whatsapp"
                val phone = call.argument<String>("phone") ?: ""
                val text = call.argument<String>("text") ?: ""
                val ok = svc?.messageAppSend(app, phone, text) ?: false
                result.success(mapOf("status" to if (ok) "opened" else "failed"))
            }

            // ═══ CONTROL GLOW (system overlay, visible over other apps) ═══

            "overlay_show" -> {
                val label = call.argument<String>("label") ?: "Jarvis is working"
                ControlOverlay.show(context, label)
                result.success(mapOf("shown" to ControlOverlay.canDraw(context)))
            }

            "overlay_update" -> {
                ControlOverlay.update(call.argument<String>("label") ?: "")
                result.success(true)
            }

            "overlay_hide" -> {
                ControlOverlay.hide()
                result.success(true)
            }

            "overlay_can_draw" -> result.success(ControlOverlay.canDraw(context))

            "overlay_request_permission" -> {
                context.startActivity(
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                           android.net.Uri.parse("package:" + context.packageName)).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
                result.success(true)
            }

            "open_notification_settings" -> {
                context.startActivity(
                    Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS").apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
                result.success(true)
            }

            "open_app" -> {
                val pkg = call.argument<String>("package") ?: return result.error("MISSING", "package required", null)
                val ok = svc?.openApp(pkg) ?: false
                result.success(mapOf("status" to if (ok) "ok" else "failed"))
            }

            "tap_text" -> {
                val text = call.argument<String>("text") ?: return result.error("MISSING", "text required", null)
                val ok = svc?.tapByText(text) ?: false
                result.success(mapOf("status" to if (ok) "tapped" else "not_found"))
            }

            "tap_description" -> {
                val desc = call.argument<String>("description") ?: return result.error("MISSING", "description required", null)
                val ok = svc?.tapByContentDescription(desc) ?: false
                result.success(mapOf("status" to if (ok) "tapped" else "not_found"))
            }

            "tap_at" -> {
                val x = call.argument<Double>("x")?.toFloat() ?: 0f
                val y = call.argument<Double>("y")?.toFloat() ?: 0f
                svc?.tapAt(x, y)
                result.success(mapOf("status" to "tapped"))
            }

            "long_press_text" -> {
                val text = call.argument<String>("text") ?: return result.error("MISSING", "text required", null)
                val ok = svc?.longPressByText(text) ?: false
                result.success(mapOf("status" to if (ok) "long_pressed" else "not_found"))
            }

            "type_text" -> {
                val text = call.argument<String>("text") ?: return result.error("MISSING", "text required", null)
                val ok = svc?.typeText(text) ?: false
                result.success(mapOf("status" to if (ok) "typed" else "failed"))
            }

            "focus_and_type" -> {
                val text = call.argument<String>("text") ?: return result.error("MISSING", "text required", null)
                val status = svc?.focusAndTypeText(text) ?: "error:service_not_enabled"
                result.success(mapOf("status" to status))
            }

            "clear_field" -> {
                val ok = svc?.clearField() ?: false
                result.success(mapOf("status" to if (ok) "cleared" else "failed"))
            }

            "press_back" -> {
                svc?.pressBack()
                result.success(mapOf("status" to "ok"))
            }

            "press_home" -> {
                svc?.pressHome()
                result.success(mapOf("status" to "ok"))
            }

            "scroll" -> {
                val direction = call.argument<String>("direction") ?: "down"
                val ok = svc?.scroll(direction) ?: false
                result.success(mapOf("status" to if (ok) "scrolled" else "failed"))
            }

            "read_screen" -> {
                val text = svc?.readScreen() ?: "(service not enabled)"
                result.success(mapOf("screen_text" to text))
            }

            // Screen contents with tap coordinates — used instead of a
            // screenshot after every action.
            "ui_tree" -> {
                val max = call.argument<Int>("max") ?: 60
                val tree = svc?.uiTree(max) ?: "(service not enabled)"
                result.success(mapOf("ui" to tree))
            }

            "screenshot" -> {
                if (svc == null) {
                    result.success(mapOf("image" to null))
                    return
                }
                svc.takeScreenshot { b64 ->
                    result.success(mapOf("image" to b64))
                }
            }

            "check_installed" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                val pm = context.packageManager
                val installed = packages.associateWith { pkg ->
                    try {
                        pm.getPackageInfo(pkg, 0)
                        true
                    } catch (e: Exception) {
                        false
                    }
                }
                result.success(mapOf("installed" to installed))
            }

            // ═══ FAST INTENTS (Siri-speed) ═══

            "play_media_fast" -> {
                val query = call.argument<String>("query") ?: return result.error("MISSING", "query required", null)
                val appPackage = call.argument<String>("app_package")
                val ok = svc?.playMediaFast(query, appPackage) ?: false
                result.success(mapOf("status" to if (ok) "launched" else "failed"))
            }

            "send_sms_fast" -> {
                val phone = call.argument<String>("phone") ?: return result.error("MISSING", "phone required", null)
                val message = call.argument<String>("message") ?: return result.error("MISSING", "message required", null)
                val ok = svc?.sendSMSFast(phone, message) ?: false
                result.success(mapOf("status" to if (ok) "launched" else "failed"))
            }

            "make_call_fast" -> {
                val phone = call.argument<String>("phone") ?: return result.error("MISSING", "phone required", null)
                val ok = svc?.makeCallFast(phone) ?: false
                result.success(mapOf("status" to if (ok) "launched" else "failed"))
            }

            "open_url_fast" -> {
                val url = call.argument<String>("url") ?: return result.error("MISSING", "url required", null)
                val ok = svc?.openUrlFast(url) ?: false
                result.success(mapOf("status" to if (ok) "launched" else "failed"))
            }

            "search_web_fast" -> {
                val query = call.argument<String>("query") ?: return result.error("MISSING", "query required", null)
                val ok = svc?.searchWebFast(query) ?: false
                result.success(mapOf("status" to if (ok) "launched" else "failed"))
            }

            "set_alarm_fast" -> {
                val hour = call.argument<Int>("hour") ?: return result.error("MISSING", "hour required", null)
                val minute = call.argument<Int>("minute") ?: return result.error("MISSING", "minute required", null)
                val message = call.argument<String>("message") ?: ""
                val ok = svc?.setAlarmFast(hour, minute, message) ?: false
                result.success(mapOf("status" to if (ok) "set" else "failed"))
            }

            else -> result.notImplemented()
        }
    }
}
