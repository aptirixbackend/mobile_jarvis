package com.nova.nova_ai

import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Reads incoming messages and replies to them without opening the app.
 *
 * WhatsApp, Messages, Telegram and the rest attach a "Reply" action to their
 * notifications — the same one your watch uses. Firing that action sends the
 * message straight from the notification, so "reply to Priya: on my way" costs
 * one action instead of: open app, find chat, tap field, type, tap send, each
 * step needing a look at the screen.
 *
 * Falls back to the accessibility route only when a conversation has no reply
 * action (rare, and true for apps that were never opened since boot).
 */
class NovaNotificationService : NotificationListenerService() {

    data class Msg(
        val key: String,
        val pkg: String,
        val sender: String,
        val text: String,
        val time: Long,
        val canReply: Boolean,
    )

    companion object {
        var instance: NovaNotificationService? = null
            private set

        fun isEnabled() = instance != null

        /** Newest first, one entry per conversation. */
        fun recent(limit: Int = 15): List<Msg> =
            instance?.snapshot(limit) ?: emptyList()
    }

    // key → the live notification, kept so we can fire its reply action later
    private val live = LinkedHashMap<String, StatusBarNotification>()

    override fun onListenerConnected() {
        instance = this
        activeNotifications?.forEach { remember(it) }
    }

    override fun onListenerDisconnected() {
        instance = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) = remember(sbn)

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        live.remove(sbn.key)
    }

    private fun remember(sbn: StatusBarNotification) {
        val extras = sbn.notification?.extras ?: return
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        if (text.isNullOrBlank()) return          // ongoing / media / silent ones
        live.remove(sbn.key)
        live[sbn.key] = sbn
        while (live.size > 40) live.remove(live.keys.first())
    }

    private fun snapshot(limit: Int): List<Msg> =
        live.values.reversed().take(limit).mapNotNull { sbn ->
            val e = sbn.notification?.extras ?: return@mapNotNull null
            val sender = e.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
            val text = e.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
            if (sender.isBlank() && text.isBlank()) return@mapNotNull null
            Msg(sbn.key, sbn.packageName, sender, text, sbn.postTime, replyAction(sbn) != null)
        }

    /** The notification's "Reply" action, if it has one. */
    private fun replyAction(sbn: StatusBarNotification): Pair<Notification.Action, RemoteInput>? {
        val actions = sbn.notification?.actions ?: return null
        for (action in actions) {
            val inputs = action.remoteInputs ?: continue
            for (input in inputs) {
                if (input.resultKey != null) return action to input
            }
        }
        return null
    }

    /**
     * Send [text] as a reply to the newest message whose sender or app matches
     * [who]. Returns the sender replied to, or null when nothing matched.
     */
    fun reply(who: String, text: String): String? {
        val needle = who.trim().lowercase()
        val target = live.values.reversed().firstOrNull { sbn ->
            val e = sbn.notification?.extras
            val sender = e?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.lowercase().orEmpty()
            val hit = needle.isEmpty() || sender.contains(needle) ||
                      sbn.packageName.lowercase().contains(needle)
            hit && replyAction(sbn) != null
        } ?: return null

        val (action, input) = replyAction(target) ?: return null
        val intent = Intent()
        val bundle = Bundle().apply { putCharSequence(input.resultKey, text) }
        RemoteInput.addResultsToIntent(arrayOf(input), intent, bundle)
        return try {
            action.actionIntent.send(this, 0, intent)
            target.notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: who
        } catch (e: Exception) {
            null
        }
    }
}
