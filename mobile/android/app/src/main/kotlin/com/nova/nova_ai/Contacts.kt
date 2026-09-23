package com.nova.nova_ai

import android.content.Context
import android.content.pm.PackageManager
import android.provider.ContactsContract

/**
 * Name → phone number, read straight from the contacts database.
 *
 * "Message amma" used to mean: open the app, tap search, type, read the
 * screen, pick a row. That is five slow steps and a guess. One query here
 * gives the number, and the chat can then be opened directly.
 */
object Contacts {

    fun find(context: Context, name: String, limit: Int = 5): List<Map<String, String>> {
        val needle = name.trim()
        if (needle.isEmpty()) return emptyList()
        if (context.checkSelfPermission(android.Manifest.permission.READ_CONTACTS)
                != PackageManager.PERMISSION_GRANTED) {
            return listOf(mapOf("error" to "no_contacts_permission"))
        }

        val out = LinkedHashMap<String, String>()   // number → display name
        val uri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        val cols = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
        )
        context.contentResolver.query(
            uri, cols,
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
            arrayOf("%$needle%"), null
        )?.use { c ->
            while (c.moveToNext() && out.size < limit) {
                val display = c.getString(0) ?: continue
                val number = (c.getString(1) ?: continue).replace(Regex("[^0-9+]"), "")
                if (number.isNotEmpty()) out.putIfAbsent(number, display)
            }
        }
        return out.entries.map { mapOf("name" to it.value, "phone" to it.key) }
    }
}
