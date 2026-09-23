package com.nova.nova_ai

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.ByteArrayOutputStream

class JarvisAccessibilityService : AccessibilityService() {

    companion object {
        var instance: JarvisAccessibilityService? = null
            private set

        fun isEnabled() = instance != null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    // ─── App launch ────────────────────────────────────────────────────────────

    fun openApp(packageName: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return true
    }

    // ─── Screen reading ────────────────────────────────────────────────────────

    fun readScreen(): String {
        val root = rootInActiveWindow ?: return ""
        val sb = StringBuilder()
        collectText(root, sb, 0)
        root.recycle()
        return sb.toString().trim()
    }

    private fun collectText(node: AccessibilityNodeInfo, sb: StringBuilder, depth: Int) {
        val text = node.text?.toString()?.trim()
        val desc = node.contentDescription?.toString()?.trim()
        val label = when {
            !text.isNullOrEmpty() -> text
            !desc.isNullOrEmpty() -> desc
            else -> null
        }
        if (!label.isNullOrEmpty()) {
            sb.append("  ".repeat(depth)).append(label).append("\n")
        }
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { child ->
                collectText(child, sb, depth + 1)
                child.recycle()
            }
        }
    }

    /**
     * What is on screen, with tap coordinates — the cheap alternative to a
     * screenshot. One line per useful node:
     *
     *   "Play" [btn] (540,1120)
     *   "Search songs" [input] (360,210)
     *
     * The model taps any of these with tap_at straight away, so a step costs a
     * few hundred characters instead of a ~200 KB image, and there is no
     * bitmap encode, no base64, and nothing to guess from pixels.
     */
    fun uiTree(max: Int = 60): String {
        val root = rootInActiveWindow ?: return ""
        val pkg = root.packageName?.toString() ?: ""
        val out = StringBuilder()
        val bounds = Rect()
        var count = 0

        fun walk(node: AccessibilityNodeInfo) {
            if (count >= max) return
            val text = node.text?.toString()?.trim()
            val desc = node.contentDescription?.toString()?.trim()
            val label = if (!text.isNullOrEmpty()) text else desc
            if (node.isVisibleToUser &&
                (node.isClickable || node.isEditable || node.isCheckable ||
                 node.isScrollable || !label.isNullOrEmpty())) {
                node.getBoundsInScreen(bounds)
                if (bounds.width() > 0 && bounds.height() > 0) {
                    val kind = when {
                        node.isEditable   -> "input"
                        node.isCheckable  -> "toggle"
                        node.isClickable  -> "btn"
                        node.isScrollable -> "list"
                        else              -> "text"
                    }
                    val shown = (label ?: node.className?.toString()?.substringAfterLast('.') ?: "?")
                        .replace("\n", " ").take(60)
                    out.append('"').append(shown).append("\" [").append(kind).append("] (")
                        .append(bounds.centerX()).append(',').append(bounds.centerY()).append(")\n")
                    count++
                }
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { child ->
                    walk(child)
                    child.recycle()
                }
            }
        }

        walk(root)
        root.recycle()
        return (if (pkg.isNotEmpty()) "app: $pkg\n" else "") + out.toString().trim()
    }

    // ─── Screenshot ────────────────────────────────────────────────────────────

    fun takeScreenshot(callback: (String?) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            takeScreenshot(
                0,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        val bitmap = Bitmap.wrapHardwareBuffer(
                            screenshot.hardwareBuffer,
                            screenshot.colorSpace
                        )
                        screenshot.hardwareBuffer.close()
                        val b64 = bitmap?.let { bitmapToBase64(it) }
                        callback(b64)
                    }

                    override fun onFailure(errorCode: Int) {
                        callback(null)
                    }
                }
            )
        } else {
            callback(null)
        }
    }

    private fun bitmapToBase64(bmp: Bitmap): String {
        // OPTIMIZED FOR SPEED: Lower resolution and quality for faster transfer
        val scaled = if (bmp.width > 720) {
            val scale = 720f / bmp.width
            Bitmap.createScaledBitmap(bmp, 720, (bmp.height * scale).toInt(), true)
        } else bmp
        val out = ByteArrayOutputStream()
        // Reduced quality from 60 to 40 for faster encoding/transfer
        scaled.compress(Bitmap.CompressFormat.JPEG, 40, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }

    // ─── Tap by text ───────────────────────────────────────────────────────────

    fun tapByText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val nodes = root.findAccessibilityNodeInfosByText(text)
        root.recycle()
        if (nodes.isNullOrEmpty()) return false
        val node = nodes[0]
        val result = clickNode(node)
        nodes.forEach { it.recycle() }
        return result
    }

    fun longPressByText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val nodes = root.findAccessibilityNodeInfosByText(text)
        root.recycle()
        if (nodes.isNullOrEmpty()) return false
        val node = nodes[0]
        val result = node.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK)
        nodes.forEach { it.recycle() }
        return result
    }

    fun tapByContentDescription(desc: String): Boolean {
        val root = rootInActiveWindow ?: return false
        var found: AccessibilityNodeInfo? = null
        findNodeByContentDescription(root, desc) { node ->
            found = node
        }
        root.recycle()
        if (found == null) return false
        val result = clickNode(found!!)
        found!!.recycle()
        return result
    }

    private fun findNodeByContentDescription(
        node: AccessibilityNodeInfo,
        targetDesc: String,
        callback: (AccessibilityNodeInfo) -> Unit
    ) {
        val nodeDesc = node.contentDescription?.toString()
        if (nodeDesc != null && nodeDesc.contains(targetDesc, ignoreCase = true)) {
            callback(node)
            return
        }
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { child ->
                findNodeByContentDescription(child, targetDesc, callback)
                child.recycle()
            }
        }
    }

    private fun clickNode(node: AccessibilityNodeInfo): Boolean {
        // Try direct click first
        if (node.isClickable) return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        // Walk up to find a clickable parent
        var parent = node.parent
        while (parent != null) {
            if (parent.isClickable) {
                val r = parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                parent.recycle()
                return r
            }
            val next = parent.parent
            parent.recycle()
            parent = next
        }
        // Fallback: gesture tap at node center
        val rect = Rect()
        node.getBoundsInScreen(rect)
        return gestureTap(rect.centerX().toFloat(), rect.centerY().toFloat())
    }

    // ─── Tap by coordinates ────────────────────────────────────────────────────

    fun tapAt(x: Float, y: Float): Boolean = gestureTap(x, y)

    private fun gestureTap(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 50)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return dispatchGesture(gesture, null, null)
    }

    // ─── Type text ─────────────────────────────────────────────────────────────

    fun typeText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        root.recycle()
        if (focused != null) {
            val args = Bundle()
            args.putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            val result = focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            focused.recycle()
            return result
        }
        return false
    }

    fun focusAndTypeText(text: String): String {
        // Try typing in already-focused field first
        val root = rootInActiveWindow ?: return "error:no_window"
        var focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        
        if (focused != null) {
            // Field is already focused, just type
            val args = Bundle()
            args.putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            val result = focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            focused.recycle()
            root.recycle()
            return if (result) "typed" else "error:set_text_failed"
        }
        
        // No field focused - find and tap an EditText
        val editText = findFirstEditText(root)
        root.recycle()
        
        if (editText == null) {
            return "error:no_input_field"
        }
        
        // Tap to focus it
        val tapped = clickNode(editText)
        if (!tapped) {
            editText.recycle()
            return "error:tap_failed"
        }
        
        // Reduced keyboard animation wait from 400ms to 250ms for speed
        Thread.sleep(250)
        
        // Now try typing
        val args = Bundle()
        args.putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        val result = editText.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        editText.recycle()
        
        return if (result) "typed_after_focus" else "error:still_failed"
    }

    private fun findFirstEditText(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // Check if this node is an editable text field
        if (node.isEditable || node.className == "android.widget.EditText") {
            return node
        }
        // Recursively search children
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findFirstEditText(child)
            if (found != null) {
                child.recycle()
                return found
            }
            child.recycle()
        }
        return null
    }

    fun clearField(): Boolean {
        val root = rootInActiveWindow ?: return false
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        root.recycle()
        if (focused != null) {
            val args = Bundle()
            args.putString(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "")
            val result = focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            focused.recycle()
            return result
        }
        return false
    }

    // ─── Scroll ────────────────────────────────────────────────────────────────

    fun scroll(direction: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val display = resources.displayMetrics
        val w = display.widthPixels.toFloat()
        val h = display.heightPixels.toFloat()
        val cx = w / 2

        val (startY, endY) = when (direction.lowercase()) {
            "up"   -> Pair(h * 0.3f, h * 0.7f)
            "down" -> Pair(h * 0.7f, h * 0.3f)
            "left" -> Pair(w * 0.8f, w * 0.2f)
            "right"-> Pair(w * 0.2f, w * 0.8f)
            else   -> Pair(h * 0.7f, h * 0.3f)
        }

        val isHorizontal = direction.lowercase() in listOf("left", "right")
        val startX = if (isHorizontal) startY else cx
        val endX   = if (isHorizontal) endY   else cx
        val sY = if (isHorizontal) h / 2 else startY
        val eY = if (isHorizontal) h / 2 else endY

        val path = Path().apply {
            moveTo(startX, sY)
            lineTo(endX, eY)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, 300)
        return dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    // ─── System actions ────────────────────────────────────────────────────────

    fun pressBack() = performGlobalAction(GLOBAL_ACTION_BACK)
    fun pressHome() = performGlobalAction(GLOBAL_ACTION_HOME)

    // ─── Fast Intents (Siri-speed actions) ────────────────────────────────────

    /**
     * Open a chat with the message already typed, then press that app's send
     * button. WhatsApp's own deep link fills the box but will not send by
     * itself, so the send button is tapped here — one action, no screen
     * reading, no guessing coordinates.
     */
    fun messageAppSend(app: String, phone: String, text: String): Boolean {
        val number = phone.replace(Regex("[^0-9+]"), "").removePrefix("+")
        try {
            val intent = when (app.lowercase()) {
                "whatsapp", "wa" -> Intent(Intent.ACTION_VIEW).apply {
                    data = android.net.Uri.parse(
                        "https://wa.me/$number?text=" + android.net.Uri.encode(text))
                    setPackage("com.whatsapp")
                }
                "telegram" -> Intent(Intent.ACTION_VIEW).apply {
                    data = android.net.Uri.parse("https://t.me/$number")
                    setPackage("org.telegram.messenger")
                }
                else -> Intent(Intent.ACTION_SENDTO).apply {   // SMS
                    data = android.net.Uri.parse("smsto:$number")
                    putExtra("sms_body", text)
                }
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            applicationContext.startActivity(intent)
        } catch (e: Exception) {
            return false
        }

        // give the chat a moment to open, then hit send
        android.os.Handler(mainLooper).postDelayed({
            for (label in listOf("Send", "send", "Send message")) {
                if (tapByContentDescription(label) || tapByText(label)) return@postDelayed
            }
        }, 1400)
        return true
    }

    fun playMediaFast(query: String, appPackage: String?): Boolean {
        try {
            val intent = Intent(android.provider.MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
                putExtra(android.provider.MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
                putExtra(android.app.SearchManager.QUERY, query)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                appPackage?.let { setPackage(it) }
            }
            applicationContext.startActivity(intent)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    fun sendSMSFast(phoneNumber: String, message: String): Boolean {
        try {
            val intent = Intent(Intent.ACTION_SENDTO).apply {
                data = android.net.Uri.parse("smsto:$phoneNumber")
                putExtra("sms_body", message)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            applicationContext.startActivity(intent)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    fun makeCallFast(phoneNumber: String): Boolean {
        try {
            val intent = Intent(Intent.ACTION_DIAL).apply {
                data = android.net.Uri.parse("tel:$phoneNumber")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            applicationContext.startActivity(intent)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    fun openUrlFast(url: String): Boolean {
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = android.net.Uri.parse(url)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            applicationContext.startActivity(intent)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    fun searchWebFast(query: String): Boolean {
        try {
            val intent = Intent(Intent.ACTION_WEB_SEARCH).apply {
                putExtra(android.app.SearchManager.QUERY, query)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            applicationContext.startActivity(intent)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    fun setAlarmFast(hour: Int, minute: Int, message: String): Boolean {
        try {
            val intent = Intent(android.provider.AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(android.provider.AlarmClock.EXTRA_HOUR, hour)
                putExtra(android.provider.AlarmClock.EXTRA_MINUTES, minute)
                putExtra(android.provider.AlarmClock.EXTRA_MESSAGE, message)
                putExtra(android.provider.AlarmClock.EXTRA_SKIP_UI, true)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            applicationContext.startActivity(intent)
            return true
        } catch (e: Exception) {
            return false
        }
    }
}
