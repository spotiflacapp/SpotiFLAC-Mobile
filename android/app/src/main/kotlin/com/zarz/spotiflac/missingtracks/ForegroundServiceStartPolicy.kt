package com.zarz.spotiflac.missingtracks

/** Maps Android/OEM foreground-service launch denials to a stable Dart code. */
object ForegroundServiceStartPolicy {
    const val START_NOT_ALLOWED_CODE = "foreground_service_start_not_allowed"

    fun isStartNotAllowed(error: Throwable): Boolean {
        if (error.javaClass.name == "android.app.ForegroundServiceStartNotAllowedException") {
            return true
        }
        val message = error.message.orEmpty()
        return message.contains("startForegroundService() not allowed", ignoreCase = true) ||
            message.contains("mAllowStartForeground false", ignoreCase = true)
    }

    fun errorCode(error: Throwable): String =
        if (isStartNotAllowed(error)) START_NOT_ALLOWED_CODE else "ERROR"
}
