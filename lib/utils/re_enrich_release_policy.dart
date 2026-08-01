enum ReEnrichOperationScope { singleFile, batch }

/// A single-file action may deliberately repair a stale release identity,
/// such as a playlist name stored in the album tag. Batch matching keeps the
/// conservative album-mismatch guard because one false match has a much larger
/// blast radius.
bool allowsReleaseIdentityReplacement(ReEnrichOperationScope scope) =>
    scope == ReEnrichOperationScope.singleFile;
