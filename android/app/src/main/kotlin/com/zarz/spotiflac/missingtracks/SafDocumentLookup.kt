package com.zarz.spotiflac.missingtracks

import android.content.Context
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile

internal fun findSafChild(
    context: Context,
    parent: DocumentFile,
    name: String,
): DocumentFile? = findSafChildren(context, parent, setOf(name))[name]

/** Reads names with IDs in one query instead of querying each child's name. */
internal fun findSafChildren(
    context: Context,
    parent: DocumentFile,
    names: Set<String>,
): Map<String, DocumentFile> {
    if (names.isEmpty()) return emptyMap()
    val children = try {
        querySafChildren(context, parent, names)
    } catch (_: Exception) {
        null
    }
    // A successful miss is final. Retry only when the provider cannot support
    // the projected query, keeping compatibility with unusual providers.
    if (children != null) return children
    return buildMap {
        for (name in names) {
            parent.findFile(name)?.let { put(name, it) }
        }
    }
}

private fun querySafChildren(
    context: Context,
    parent: DocumentFile,
    names: Set<String>,
): Map<String, DocumentFile>? {
    val parentUri = parent.uri
    if (!DocumentsContract.isTreeUri(parentUri)) return null
    val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
        parentUri,
        DocumentsContract.getDocumentId(parentUri),
    )
    val projection = arrayOf(
        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
    )
    val cursor = context.contentResolver.query(childrenUri, projection, null, null, null)
        ?: return null
    return cursor.use {
        val idColumn = it.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
        val nameColumn = it.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        if (idColumn < 0 || nameColumn < 0) return null
        val found = linkedMapOf<String, DocumentFile>()
        while (it.moveToNext()) {
            val name = it.getString(nameColumn) ?: continue
            if (name !in names || name in found) continue
            val id = it.getString(idColumn)?.takeIf(String::isNotEmpty) ?: return null
            val childUri = DocumentsContract.buildDocumentUriUsingTree(parentUri, id)
            // AndroidX 1.1.0 preserves the child ID in a tree document URI.
            // fromSingleUri would disable directory operations and rename.
            val child = DocumentFile.fromTreeUri(context, childUri) ?: return null
            found[name] = child
            if (found.size == names.size) break
        }
        found
    }
}
