package com.zarz.spotiflac.missingtracks

import java.util.LinkedHashSet

/**
 * Serializes work per key while allowing idle key entries to be reclaimed.
 * References are counted before a caller waits on the monitor, so a waiter can
 * never race with removal and end up using a different monitor for the same key.
 */
internal class KeyedLockPool<K> {
    private class Entry {
        val monitor = Any()
        var references = 0
    }

    private val registryLock = Any()
    private val entries = HashMap<K, Entry>()

    fun <T> withLock(key: K, block: () -> T): T {
        val entry = synchronized(registryLock) {
            entries.getOrPut(key) { Entry() }.also { it.references++ }
        }
        try {
            return synchronized(entry.monitor) { block() }
        } finally {
            synchronized(registryLock) {
                entry.references--
                if (entry.references == 0 && entries[key] === entry) {
                    entries.remove(key)
                }
            }
        }
    }

    internal fun activeKeyCount(): Int = synchronized(registryLock) {
        entries.size
    }
}

/** A small insertion-ordered registry that consumes completed IDs. */
internal class BoundedRegistry<T>(private val maxEntries: Int) {
    private val lock = Any()
    private val values = LinkedHashSet<T>()

    init {
        require(maxEntries > 0) { "maxEntries must be greater than zero" }
    }

    fun add(value: T) = synchronized(lock) {
        values.remove(value)
        values.add(value)
        while (values.size > maxEntries) {
            val oldest = values.iterator().next()
            values.remove(oldest)
        }
    }

    fun consume(value: T): Boolean = synchronized(lock) {
        values.remove(value)
    }

    internal fun size(): Int = synchronized(lock) { values.size }
}
