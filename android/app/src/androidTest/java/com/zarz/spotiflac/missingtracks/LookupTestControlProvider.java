package com.zarz.spotiflac.missingtracks;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Bundle;

/** Issues fixture setup calls from the test APK's UID, never the app UID. */
public final class LookupTestControlProvider extends ContentProvider {
    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Bundle call(String method, String arg, Bundle extras) {
        if (!method.startsWith("lookup.")) throw new IllegalArgumentException(method);
        long identity = Binder.clearCallingIdentity();
        try {
            return getContext().getContentResolver().call(
                Uri.parse("content://com.spotiflac.test.documents.lookup"), method, arg, extras
            );
        } finally {
            Binder.restoreCallingIdentity(identity);
        }
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] args, String order) {
        return null;
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        return null;
    }

    @Override
    public int delete(Uri uri, String selection, String[] args) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] args) {
        return 0;
    }
}
