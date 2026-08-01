# SpotiFLAC Mobile Extension Development

This guide defines the extension package and manifest contract implemented by
the current SpotiFLAC Mobile codebase. The expanded runtime API reference is
available at <https://spotiflac.zarz.moe/docs>.

## Quick start

Create a directory with these two root files:

```text
my-extension/
├── manifest.json
└── index.js
```

Use the current camel-case manifest schema:

```json
{
  "name": "my-extension",
  "displayName": "My Extension",
  "version": "1.0.0",
  "description": "What this extension provides",
  "homepage": "https://github.com/you/my-extension",
  "type": ["metadata_provider"],
  "minAppVersion": "4.2.3",
  "permissions": {
    "network": ["api.example.com", "*.example.com"],
    "storage": false,
    "file": false
  },
  "settings": []
}
```

Register the implementation from `index.js`:

```js
registerExtension({
  searchTracks: async function (query, limit) {
    const response = await http.get(
      "https://api.example.com/search?q=" +
        encodeURIComponent(query) +
        "&limit=" +
        String(limit)
    );

    return {
      tracks: response.data.items.map((item) => ({
        id: String(item.id),
        name: item.title,
        artist: item.artist,
        album_name: item.album,
        duration_ms: item.duration_ms,
        cover_url: item.cover_url
      })),
      total: response.data.total
    };
  }
});
```

Package the contents—not their parent directory—as ZIP:

```bash
cd my-extension
zip -r ../my-extension.sflx manifest.json index.js
```

An extension package is a plain ZIP archive renamed to `.sflx`. The longer
`.spotiflac-ext` suffix is the legacy alias; both are accepted everywhere
(manual import, repo downloads) and the layout is identical. Use `.sflx` for
new packages.

`manifest.json` and `index.js` must be unique files at the archive root.
SpotiFLAC Mobile rejects traversal paths, symlinks, duplicate paths, oversized
manifests, and archives whose extracted size exceeds the safety limit.

## Manifest contract

The parser lives in
[`go_backend/extension_manifest.go`](../go_backend/extension_manifest.go).
Use these exact field names:

| Field | Required | Contract |
| --- | --- | --- |
| `name` | yes | Stable lowercase ID matching `^[a-z0-9][a-z0-9._-]{0,127}$` |
| `displayName` | recommended | Human-readable Store and settings label |
| `version` | yes | Numeric dotted version used by upgrade comparison |
| `description` | yes | Human-readable purpose |
| `type` | yes | Array containing `metadata_provider`, `download_provider`, or `lyrics_provider` |
| `permissions` | yes | Capability object described below |
| `homepage`, `icon`, `minAppVersion` | no | `icon` is a path inside the package |
| `settings` | no | Extension settings shown by the app |
| `qualityOptions` | download provider | Download quality IDs passed to `download()` |
| `searchBehavior` | no | Generic search-tab behavior |
| `urlHandler` | no | URL matching declarations |
| `trackMatching` | no | Generic matching strategy |
| `postProcessing` | no | Generic post-processing hooks |
| `serviceHealth` | no | Health checks shown by the app |
| `signedSession` | no | Signed-session bootstrap contract |
| `requiredRuntimeFeatures` | no | Runtime feature requirements |
| `capabilities` | no | Generic extension capability declarations |

The behavior flags currently supported are `skipMetadataEnrichment`,
`skipLyrics`, `stopProviderFallback`, and `skipBuiltInFallback`. New
extension-specific behavior must be added as a generic manifest capability;
the host must not branch on a particular provider ID.

Extensions that depend on canonical gateway/provider error ownership should
declare `requiredRuntimeFeatures: ["signedSession@2"]`. Version 2 only mutates
gateway session state for the exact `SESSION_INVALID/bootstrap_session` or
`VERIFY_REQUIRED/verify` contracts, exposes canonical error fields to JS, and
keeps provider-owned failures separate. `403 REQUEST_AUTH_INVALID` preserves
the session and only retries once when a newer session generation is already
available. BYOA
reauthentication remains a separate provider action. An active generation that
receives canonical `428 VERIFY_REQUIRED` is blocked in the shared coordinator,
so later requests join the same verification flow instead of hitting the
gateway repeatedly.

Extensions that depend on provider retry modes should require
`signedSession@3`. The runtime exposes `retryMode` and only auto-retries
`PROVIDER_UNAVAILABLE` when `retryable: true` is paired with
`retry_mode: "same_operation"`. Every such retry is newly signed with a fresh
timestamp and nonce. `new_ticket`, `poll_existing`, `none`, missing, and unknown
modes are returned to the extension without automatic replay.

Do not use legacy spellings such as `display_name`, `types`,
`permissions.network.domains`, or an object for `permissions.network`.

### Permissions

```json
{
  "permissions": {
    "network": ["api.example.com", "*.cdn.example.com"],
    "storage": true,
    "file": false,
    "allowHttp": false
  }
}
```

- `network` is an array of allowed host names. HTTPS is required unless
  `allowHttp` is explicitly enabled.
- `storage` is required for extension storage and signed-session state.
- `file` is required for file and raw FFmpeg capabilities.

Request only what the extension needs. The runtime denies undeclared network,
storage, and file access.

## Downloading files

Extensions with `permissions.file: true` can stream a remote file into their
allowed output path:

```js
const result = file.download(downloadUrl, outputPath, {
  headers: {
    "User-Agent": "My Extension/1.0"
  },
  onProgress: function (written, total) {
    log.debug("Downloaded", written, "of", total, "bytes");
  },
  resume: true
});
```

The third argument is optional and supports:

| Option | Type | Default | Contract |
| --- | --- | --- | --- |
| `headers` | object | `{}` | Additional request headers. Do not set `Range` when using runtime-managed resume. |
| `onProgress` | function | none | Called as `onProgress(writtenBytes, totalBytes)` when the total is known. |
| `trackItemBytes` | boolean | `true` | Publishes byte progress to the host download queue. The legacy alias `track_item_bytes` is also accepted. |
| `resume` | boolean | `false` | Allows up to three mid-body Range resumes for the normal streaming mode. |
| `chunked` | boolean or positive number | `false` | Uses sequential Range requests. `true` selects 1 MiB chunks; a positive number sets the chunk size in bytes. |

`resume` is deliberately opt-in. It is attempted only when the server returns
a strong `ETag` or `Last-Modified` validator. Resumed responses must return the
expected `206 Content-Range`; if the server returns `200`, the staged file is
truncated and restarted from byte zero. Enable it only when the origin
guarantees that the same URL and validator identify byte-identical content
across retries and network changes. A CDN can otherwise splice bytes from two
different objects into one apparently successful file.

Use `chunked` for origins that require bounded Range requests, such as some
media CDNs. Chunked mode has its own per-chunk retries and does not use the
`resume` option. In every mode SpotiFLAC Mobile writes to a staged sibling file
and publishes the final path only after the download completes successfully.

## Store registry integrity

Repository maintainers should publish a SHA-256 digest for every package:

```json
{
  "version": 1,
  "extensions": [
    {
      "id": "my-extension",
      "name": "my-extension",
      "display_name": "My Extension",
      "version": "1.0.0",
      "description": "What this extension provides",
      "category": "metadata",
      "download_url": "https://example.com/my-extension.sflx",
      "sha256": "64-lowercase-hex-characters"
    }
  ]
}
```

Generate the digest after building the package:

```bash
sha256sum my-extension.sflx
```

Store downloads with a published digest are written to a temporary file,
hashed, and only moved into place after the digest matches. A mismatch aborts
installation and preserves any previously cached package. Legacy registry
entries without `sha256` remain compatible but cannot provide package
integrity verification.

A checksum authenticates a package only as strongly as the HTTPS registry that
publishes it. A manually imported `.spotiflac-ext` or `.sflx` package has no
registry trust context, so install manual packages only from a publisher you
trust.

## Compatibility checklist

Before publishing:

1. Validate that `manifest.json` uses the exact current field names.
2. Keep `manifest.json` and `index.js` at the archive root.
3. Declare every network host and runtime permission used.
4. Set `minAppVersion` when relying on a recently added capability.
5. Test install, enable, disable, upgrade, and removal.
6. Publish the package SHA-256 in the repository registry.
