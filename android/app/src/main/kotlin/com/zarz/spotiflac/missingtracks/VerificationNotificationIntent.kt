package com.zarz.spotiflac.missingtracks

import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.util.UUID

internal object VerificationNotificationIntent {
    const val ACTION = "com.zarz.spotiflac.missingtracks.VERIFY_EXTENSION"
    const val PAYLOAD = "verification_payload"

    fun create(context: Context, extensionId: String, itemId: String): Intent {
        val payload = JSONObject()
            .put("kind", "extension_verification")
            .put("extension_id", extensionId)
            .put("item_id", itemId)
            .put("tap_id", "native:${UUID.randomUUID()}")
        return Intent(context, MainActivity::class.java)
            .setAction(ACTION)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(PAYLOAD, payload.toString())
    }
}
