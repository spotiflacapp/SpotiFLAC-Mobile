//! File capabilities granted by the native manager, never by JavaScript.

mod index;

use cap_std::ambient_authority;
use cap_std::fs::{Dir, File, OpenOptions};
use std::collections::BTreeMap;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex, RwLock, Weak};
use std::thread::{self, ThreadId};
use std::time::Duration;

pub(crate) const MAX_READ: usize = 16 << 20;
pub(crate) const READ_LIMIT_ERROR: &str = "file read exceeds 16 MiB limit; use file.readBytes with offset and length to read it in chunks";

struct Root {
    path: PathBuf,
    directory: Dir,
}

impl Root {
    fn open(path: &Path) -> io::Result<Arc<Self>> {
        let path = clean(&std::path::absolute(path)?);
        std::fs::create_dir_all(&path)?;
        Ok(Arc::new(Self {
            directory: Dir::open_ambient_dir(&path, ambient_authority())?,
            path,
        }))
    }
}

#[derive(Default)]
pub struct FileRegistry {
    allowed: RwLock<Vec<Arc<Root>>>,
    temporary: RwLock<Vec<Weak<Root>>>,
    outputs: Mutex<BTreeMap<PathBuf, Weak<OutputLock>>>,
}

/// Retain one host-created download directory while its provider is running.
/// Open file capabilities may outlive the grant; future opens may not.
pub struct TemporaryGrant {
    root: Arc<Root>,
    registry: Arc<FileRegistry>,
}

impl Drop for TemporaryGrant {
    fn drop(&mut self) {
        let key = Arc::downgrade(&self.root);
        self.registry
            .temporary
            .write()
            .expect("temporary file grants lock")
            .retain(|root| !Weak::ptr_eq(root, &key));
    }
}

impl FileRegistry {
    /// Replace the native download-directory grants for future operations.
    /// Open descriptors keep an in-progress operation bound to its original root.
    pub fn set_allowed_directories(&self, paths: &[PathBuf]) -> io::Result<()> {
        let roots = paths
            .iter()
            .map(|path| Root::open(path))
            .collect::<io::Result<Vec<_>>>()?;
        *self.allowed.write().expect("file grants lock") = roots;
        Ok(())
    }

    pub(crate) fn grant_temporary_directory(
        self: &Arc<Self>,
        path: &Path,
    ) -> io::Result<TemporaryGrant> {
        let root = Root::open(path)?;
        let mut temporary = self.temporary.write().expect("temporary file grants lock");
        temporary.retain(|root| root.strong_count() != 0);
        temporary.push(Arc::downgrade(&root));
        Ok(TemporaryGrant {
            root,
            registry: Arc::clone(self),
        })
    }

    pub fn extension(self: &Arc<Self>, directory: &Path) -> io::Result<Arc<ExtensionFiles>> {
        self.extension_with_alias(directory, directory)
    }

    pub(crate) fn extension_with_alias(
        self: &Arc<Self>,
        directory: &Path,
        alias: &Path,
    ) -> io::Result<Arc<ExtensionFiles>> {
        let root = Root::open(directory)?;
        let alias = clean(&std::path::absolute(alias)?);
        let alias = if alias == root.path {
            None
        } else if std::fs::canonicalize(&alias)? == std::fs::canonicalize(&root.path)? {
            Some(alias)
        } else {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "sandbox alias refers to a different directory",
            ));
        };
        Ok(Arc::new(ExtensionFiles {
            root,
            legacy_alias: alias,
            registry: Arc::clone(self),
        }))
    }

    pub(crate) fn validate_native_replacement(
        &self,
        path: &str,
        bases: &[PathBuf],
    ) -> Result<(), String> {
        let target = clean(Path::new(path));
        let granted = self.allowed.read().expect("file grants lock");
        let temporary: Vec<_> = self
            .temporary
            .read()
            .expect("temporary file grants lock")
            .iter()
            .filter_map(Weak::upgrade)
            .collect();
        for base in bases
            .iter()
            .chain(granted.iter().chain(&temporary).map(|root| &root.path))
        {
            let base = clean(&std::path::absolute(base).map_err(|error| error.to_string())?);
            if let Ok(relative) = target.strip_prefix(&base) {
                let directory = match Dir::open_ambient_dir(&base, ambient_authority()) {
                    Ok(directory) => directory,
                    // Go accepts a future output path; validation must not create it.
                    Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
                    Err(error) => return Err(error.to_string()),
                };
                return FilePath {
                    root: Arc::new(Root {
                        path: base.clone(),
                        directory,
                    }),
                    absolute: target.clone(),
                    relative: relative.into(),
                }
                .native_display()
                .map(|_| ());
            }
        }
        Err("replacement file path is outside allowed directories".into())
    }

    fn lock(
        &self,
        path: &Path,
        check: &dyn Fn() -> Result<(), String>,
    ) -> Result<OutputGuard, String> {
        let lock = {
            let mut outputs = self.outputs.lock().expect("file outputs lock");
            outputs.retain(|_, value| value.strong_count() > 0);
            let lock = outputs
                .get(path)
                .and_then(Weak::upgrade)
                .unwrap_or_default();
            outputs.insert(path.to_owned(), Arc::downgrade(&lock));
            lock
        };
        let mut owner = lock.owner.lock().expect("file owner lock");
        while let Some(id) = *owner {
            check()?;
            if id == thread::current().id() {
                return Err("file output is already in use by this callback".into());
            }
            owner = lock
                .idle
                .wait_timeout(owner, Duration::from_millis(10))
                .expect("file output wait")
                .0;
        }
        check()?;
        *owner = Some(thread::current().id());
        drop(owner);
        Ok(OutputGuard(lock))
    }
}

pub struct ExtensionFiles {
    root: Arc<Root>,
    legacy_alias: Option<PathBuf>,
    registry: Arc<FileRegistry>,
}

impl ExtensionFiles {
    pub(crate) fn resolve_legacy(&self, path: &str) -> Result<FilePath, String> {
        let original = Path::new(path);
        let path = clean(original);
        if path.is_absolute() {
            for root in std::iter::once(&self.root.path).chain(self.legacy_alias.as_ref()) {
                if let Ok(relative) = path.strip_prefix(root) {
                    if root != &self.root.path
                        && !std::fs::canonicalize(root).is_ok_and(|alias| {
                            std::fs::canonicalize(&self.root.path)
                                .is_ok_and(|canonical| alias == canonical)
                        })
                    {
                        return Err(
                            "file access denied: sandbox alias refers to a different directory"
                                .into(),
                        );
                    }
                    let mut resolved =
                        self.resolve(relative.to_str().ok_or("invalid UTF-8 path")?)?;
                    // Keep native path spelling in cache keys and results while
                    // opening through the original sandbox capability.
                    resolved.absolute = original.to_owned();
                    return Ok(resolved);
                }
            }
        }
        let mut resolved = self.resolve(path.to_str().ok_or("invalid UTF-8 path")?)?;
        if original.is_absolute() {
            resolved.absolute = original.to_owned();
        }
        Ok(resolved)
    }

    pub(crate) fn resolve(&self, path: &str) -> Result<FilePath, String> {
        let input = clean(Path::new(path));
        let (root, absolute) = if input.is_absolute() {
            let root = self
                .registry
                .allowed
                .read()
                .expect("file grants lock")
                .iter()
                .find(|root| input.starts_with(&root.path))
                .cloned();
            let root = root.or_else(|| self.registry.temporary.read().expect("temporary file grants lock")
                .iter().filter_map(Weak::upgrade).find(|root| input.starts_with(&root.path)))
                .ok_or("file access denied: absolute paths are not allowed. Use relative paths within extension sandbox")?;
            (root, input)
        } else {
            let absolute = clean(&self.root.path.join(input));
            if !absolute.starts_with(&self.root.path) {
                return Err(format!(
                    "file access denied: path '{path}' is outside sandbox"
                ));
            }
            (Arc::clone(&self.root), absolute)
        };
        let relative = absolute
            .strip_prefix(&root.path)
            .expect("validated file root")
            .to_owned();
        Ok(FilePath {
            root,
            absolute,
            relative: if relative.as_os_str().is_empty() {
                ".".into()
            } else {
                relative
            },
        })
    }

    pub(crate) fn lock(
        &self,
        path: &FilePath,
        check: &dyn Fn() -> Result<(), String>,
    ) -> Result<OutputGuard, String> {
        // Go coordinates case-folded paths, including aliases on the default
        // case-insensitive mobile/macOS filesystems.
        self.registry
            .lock(Path::new(&path.display().to_lowercase()), check)
    }
}

pub(crate) struct FilePath {
    root: Arc<Root>,
    pub absolute: PathBuf,
    relative: PathBuf,
}

impl FilePath {
    /// Native FFmpeg opens a pathname rather than this capability descriptor.
    /// Reject existing symlinks and special files before handing it to native.
    /// The adapter must retain exclusive ownership of these paths through use.
    pub(crate) fn native_display(&self) -> Result<String, String> {
        let mut path = PathBuf::new();
        for component in self.relative.components() {
            path.push(component);
            match self.root.directory.symlink_metadata(&path) {
                Ok(metadata) => {
                    if metadata.is_symlink() || (!metadata.is_file() && !metadata.is_dir()) {
                        return Err(
                            "native media path must not contain symlinks or special files".into(),
                        );
                    }
                }
                Err(error) if error.kind() == io::ErrorKind::NotFound => break,
                Err(error) => return Err(error.to_string()),
            }
        }
        Ok(self.display())
    }

    pub(crate) fn open_parent(&self) -> io::Result<(Dir, std::ffi::OsString)> {
        self.mkdir_parent()?;
        let name = self.relative.file_name().ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidInput, "invalid output filename")
        })?;
        Ok((
            self.root.directory.open_dir(self.parent())?,
            name.to_owned(),
        ))
    }

    pub fn display(&self) -> String {
        self.absolute.to_string_lossy().into_owned()
    }

    pub fn metadata(&self) -> io::Result<cap_std::fs::Metadata> {
        self.root.directory.metadata(&self.relative)
    }

    /// Validates only the final component, for walkers whose parent directory
    /// was already checked by [`Self::native_display`] or by this method. One
    /// lstat replaces a per-component walk plus separate size and time stats.
    pub(crate) fn native_child_metadata(&self) -> io::Result<cap_std::fs::Metadata> {
        let metadata = self.root.directory.symlink_metadata(&self.relative)?;
        if metadata.is_symlink() || (!metadata.is_file() && !metadata.is_dir()) {
            return Err(io::Error::other(
                "native media path must not contain symlinks or special files",
            ));
        }
        Ok(metadata)
    }

    pub(crate) fn entries(&self) -> io::Result<Vec<(String, bool)>> {
        let mut entries = self
            .root
            .directory
            .read_dir(&self.relative)?
            .map(|entry| {
                let entry = entry?;
                Ok((
                    entry.file_name().to_string_lossy().into_owned(),
                    entry.file_type()?.is_dir(),
                ))
            })
            .collect::<io::Result<Vec<_>>>()?;
        entries.sort_by(|a, b| a.0.cmp(&b.0));
        Ok(entries)
    }

    pub fn mkdir_parent(&self) -> io::Result<()> {
        self.root.directory.create_dir_all(self.parent())
    }

    pub(crate) fn require_parent(&self) -> Result<(), String> {
        self.root
            .directory
            .open_dir(self.parent())
            .map(|_| ())
            .map_err(|error| error.to_string())
    }

    fn parent(&self) -> &Path {
        self.relative
            .parent()
            .filter(|path| !path.as_os_str().is_empty())
            .unwrap_or(Path::new("."))
    }

    pub fn open(&self, options: &mut OpenOptions) -> io::Result<File> {
        #[cfg(unix)]
        {
            use cap_std::fs::OpenOptionsExt;
            // FIFOs/devices must not block a VM worker before cancellation can
            // run. Only regular files are accepted after opening the descriptor.
            options
                .custom_flags(rustix::fs::OFlags::NONBLOCK.bits() as i32)
                .mode(0o644);
        }
        let file = self.root.directory.open_with(&self.relative, options)?;
        if !file.metadata()?.is_file() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "not a regular file",
            ));
        }
        Ok(file)
    }

    /// Open a native read through its granted directory, rejecting symlinks at
    /// every component without separately walking the same path for validation.
    #[cfg(unix)]
    pub(crate) fn open_native_read(&self) -> io::Result<File> {
        use rustix::fd::{AsFd, OwnedFd};
        use rustix::fs::{AtFlags, FileType, Mode, OFlags, openat, statat};

        let mut directory: Option<OwnedFd> = None;
        let mut components = self.relative.components().peekable();
        while let Some(component) = components.next() {
            if !matches!(component, Component::Normal(_) | Component::CurDir) {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "invalid native path",
                ));
            }
            let name = component.as_os_str();
            let parent = directory
                .as_ref()
                .map_or_else(|| self.root.directory.as_fd(), AsFd::as_fd);
            let last = components.peek().is_none();
            let mut flags = OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK;
            if !last {
                flags |= OFlags::DIRECTORY;
                // Match capability traversal: a known child only needs search
                // permission on its parents, not permission to list them.
                #[cfg(any(target_os = "linux", target_os = "android"))]
                {
                    flags |= OFlags::PATH;
                }
            }
            let fd = match openat(parent, name, flags, Mode::empty()) {
                Ok(fd) => fd,
                Err(error) => {
                    // Preserve the native-path error for links and special
                    // files even when a platform reports ENOTDIR or ENXIO.
                    if error != rustix::io::Errno::NOENT
                        && let Ok(info) = statat(parent, name, AtFlags::SYMLINK_NOFOLLOW)
                    {
                        let kind = FileType::from_raw_mode(info.st_mode);
                        if !matches!(kind, FileType::RegularFile | FileType::Directory) {
                            return Err(io::Error::other(
                                "native media path must not contain symlinks or special files",
                            ));
                        }
                    }
                    return Err(error.into());
                }
            };
            if last {
                let file = std::fs::File::from(fd);
                let metadata = file.metadata()?;
                if metadata.is_file() {
                    return Ok(File::from_std(file));
                }
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    if metadata.is_dir() {
                        "not a regular file"
                    } else {
                        "native media path must not contain symlinks or special files"
                    },
                ));
            }
            directory = Some(fd);
        }
        Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "empty native path",
        ))
    }

    #[cfg(not(unix))]
    pub(crate) fn open_native_read(&self) -> io::Result<File> {
        self.native_display().map_err(io::Error::other)?;
        self.open(OpenOptions::new().read(true))
    }

    pub fn remove(&self) -> io::Result<()> {
        let info = self.root.directory.symlink_metadata(&self.relative)?;
        if info.is_dir() {
            self.root.directory.remove_dir(&self.relative)
        } else {
            self.root.directory.remove_file(&self.relative)
        }
    }

    pub fn rename_to(&self, target: &Self) -> io::Result<()> {
        self.root
            .directory
            .rename(&self.relative, &target.root.directory, &target.relative)
    }

    pub fn stage(&self) -> io::Result<StagedFile> {
        self.stage_with_parent(true, None).map(|(stage, _)| stage)
    }

    pub(crate) fn stage_existing_parent(&self) -> io::Result<StagedFile> {
        self.stage_with_parent(false, None).map(|(stage, _)| stage)
    }

    /// Link a completed private provider file into staging without copying its
    /// bytes. Verify the link against the caller's open descriptor before use.
    pub(crate) fn stage_from(&self, input: &Self, source: &File) -> io::Result<(StagedFile, bool)> {
        self.stage_with_parent(true, Some((input, source)))
    }

    fn stage_with_parent(
        &self,
        create_parent: bool,
        source: Option<(&Self, &File)>,
    ) -> io::Result<(StagedFile, bool)> {
        if create_parent {
            self.mkdir_parent()?;
        }
        let parent = self.root.directory.open_dir(self.parent())?;
        let target = self
            .relative
            .file_name()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "invalid output filename"))?
            .to_owned();
        for _ in 0..8 {
            let mut nonce = [0; 16];
            getrandom::fill(&mut nonce).map_err(|error| io::Error::other(error.to_string()))?;
            let name = format!(
                ".spotiflac-{}.partial",
                crate::binary::encode(&nonce, "hex").expect("hex encoding")
            );
            #[cfg(unix)]
            if let Some((input, source)) = source {
                use cap_std::fs::MetadataExt;
                match input
                    .root
                    .directory
                    .hard_link(&input.relative, &parent, &name)
                {
                    Ok(()) => {
                        let linked = rustix::fs::openat(
                            &parent,
                            &name,
                            rustix::fs::OFlags::RDONLY
                                | rustix::fs::OFlags::NOFOLLOW
                                | rustix::fs::OFlags::CLOEXEC,
                            rustix::fs::Mode::empty(),
                        )
                        .map(|fd| File::from_std(std::fs::File::from(fd)))
                        .map_err(io::Error::from);
                        let linked = linked.and_then(|file| {
                            let actual = file.metadata()?;
                            let expected = source.metadata()?;
                            if actual.is_file()
                                && actual.dev() == expected.dev()
                                && actual.ino() == expected.ino()
                            {
                                Ok(file)
                            } else {
                                Err(io::Error::other(
                                    "provider source changed before publication",
                                ))
                            }
                        });
                        if let Ok(file) = linked {
                            return Ok((
                                StagedFile {
                                    parent,
                                    name,
                                    target,
                                    file,
                                    published: false,
                                },
                                true,
                            ));
                        }
                        parent.remove_file(&name)?;
                    }
                    Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                    // Cross-device and filesystems without hard links retain
                    // the descriptor-based copy path below.
                    Err(_) => {}
                }
            }
            #[cfg(not(unix))]
            let _ = source;
            let mut options = OpenOptions::new();
            options.read(true).write(true).create_new(true);
            #[cfg(unix)]
            {
                use cap_std::fs::OpenOptionsExt;
                options.mode(0o644);
            }
            match parent.open_with(&name, &options) {
                Ok(file) => {
                    return Ok((
                        StagedFile {
                            parent,
                            name,
                            target,
                            file,
                            published: false,
                        },
                        false,
                    ));
                }
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
        Err(io::Error::other("unable to allocate staged output"))
    }
}

pub(crate) struct StagedFile {
    parent: Dir,
    name: String,
    target: std::ffi::OsString,
    pub file: File,
    published: bool,
}

#[cfg(any(target_vendor = "apple", target_os = "linux", target_os = "android"))]
fn publish_without_noreplace(
    parent: &Dir,
    name: &str,
    target: &std::ffi::OsStr,
    error: rustix::io::Errno,
) -> io::Result<()> {
    use rustix::fs::{AtFlags, statat};
    use rustix::io::Errno;

    if !matches!(error, Errno::INVAL | Errno::NOSYS | Errno::OPNOTSUPP) {
        return Err(error.into());
    }
    match statat(parent, target, AtFlags::SYMLINK_NOFOLLOW) {
        Ok(_) => Err(io::ErrorKind::AlreadyExists.into()),
        Err(Errno::NOENT) => parent.rename(name, parent, target),
        Err(error) => Err(error.into()),
    }
}

#[cfg(all(
    test,
    any(target_vendor = "apple", target_os = "linux", target_os = "android")
))]
mod publish_noreplace_fallback_tests {
    use super::*;
    use rustix::io::Errno;

    #[test]
    fn unsupported_noreplace_errors_publish_only_when_target_is_absent() {
        for error in [Errno::INVAL, Errno::NOSYS, Errno::OPNOTSUPP] {
            let root = tempfile::tempdir().unwrap();
            let parent = Dir::open_ambient_dir(root.path(), ambient_authority()).unwrap();
            parent.write("staged", b"new audio").unwrap();
            publish_without_noreplace(&parent, "staged", "track.opus".as_ref(), error).unwrap();
            assert_eq!(parent.read("track.opus").unwrap(), b"new audio");

            parent.write("staged", b"replacement").unwrap();
            let result = publish_without_noreplace(&parent, "staged", "track.opus".as_ref(), error);
            assert_eq!(result.unwrap_err().kind(), io::ErrorKind::AlreadyExists);
            assert_eq!(parent.read("track.opus").unwrap(), b"new audio");
        }
    }

    #[test]
    fn unrelated_rename_error_does_not_publish() {
        let root = tempfile::tempdir().unwrap();
        let parent = Dir::open_ambient_dir(root.path(), ambient_authority()).unwrap();
        parent.write("staged", b"new audio").unwrap();
        let result =
            publish_without_noreplace(&parent, "staged", "track.opus".as_ref(), Errno::ACCESS);
        assert_eq!(
            result.unwrap_err().raw_os_error(),
            Some(Errno::ACCESS.raw_os_error())
        );
        assert!(parent.metadata("staged").is_ok());
        assert!(parent.metadata("track.opus").is_err());
    }
}

impl StagedFile {
    /// Album resolution must not replace a file created by another publisher
    /// after the planner checked the destination. Both names are in this parent.
    pub fn publish_new(mut self, check: &dyn Fn() -> Result<(), String>) -> io::Result<()> {
        self.file.sync_all()?;
        check().map_err(io::Error::other)?;
        #[cfg(any(target_vendor = "apple", target_os = "linux", target_os = "android"))]
        if let Err(error) = rustix::fs::renameat_with(
            &self.parent,
            &self.name,
            &self.parent,
            &self.target,
            rustix::fs::RenameFlags::NOREPLACE,
        ) {
            publish_without_noreplace(&self.parent, &self.name, &self.target, error)?;
        }
        #[cfg(not(any(target_vendor = "apple", target_os = "linux", target_os = "android")))]
        {
            self.parent
                .hard_link(&self.name, &self.parent, &self.target)?;
            let _ = self.parent.remove_file(&self.name);
        }
        self.published = true;
        let _ = self
            .parent
            .try_clone()
            .and_then(|parent| parent.into_std_file().sync_all());
        Ok(())
    }

    pub fn publish(mut self, check: &dyn Fn() -> Result<(), String>) -> Result<(), String> {
        self.file.sync_all().map_err(|error| error.to_string())?;
        check()?;
        self.parent
            .rename(&self.name, &self.parent, &self.target)
            .map_err(|error| error.to_string())?;
        self.published = true;
        // Match native tag/download publication durability where the filesystem
        // supports directory fsync. Unsupported directory sync is best-effort.
        let _ = self
            .parent
            .try_clone()
            .and_then(|parent| parent.into_std_file().sync_all());
        Ok(())
    }
}

impl Drop for StagedFile {
    fn drop(&mut self) {
        if !self.published {
            let _ = self.parent.remove_file(&self.name);
        }
    }
}

#[derive(Default)]
struct OutputLock {
    owner: Mutex<Option<ThreadId>>,
    idle: Condvar,
}

pub(crate) struct OutputGuard(Arc<OutputLock>);

impl Drop for OutputGuard {
    fn drop(&mut self) {
        *self.0.owner.lock().expect("file owner lock") = None;
        self.0.idle.notify_all();
    }
}

pub(crate) fn clean(path: &Path) -> PathBuf {
    let mut result = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                if result.file_name().is_some_and(|name| name != "..") {
                    result.pop();
                } else if !result.has_root() {
                    result.push("..");
                }
            }
            _ => result.push(component),
        }
    }
    if result.as_os_str().is_empty() {
        ".".into()
    } else {
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Seek, SeekFrom, Write};

    #[cfg(unix)]
    #[test]
    fn native_reads_reject_links_at_every_component_and_never_write_or_wait_on_special_files() {
        use std::io::Read;
        use std::os::unix::{fs::symlink, net::UnixListener};

        let root = tempfile::tempdir().unwrap();
        let files = Arc::new(FileRegistry::default())
            .extension(root.path())
            .unwrap();
        std::fs::create_dir_all(root.path().join("album/disc")).unwrap();
        std::fs::write(root.path().join("album/disc/song.wav"), b"original").unwrap();
        #[cfg(any(target_os = "linux", target_os = "android"))]
        {
            use std::os::unix::fs::PermissionsExt;
            let parent = root.path().join("album");
            std::fs::set_permissions(&parent, std::fs::Permissions::from_mode(0o111)).unwrap();
            let result = files
                .resolve("album/disc/song.wav")
                .unwrap()
                .open_native_read();
            std::fs::set_permissions(&parent, std::fs::Permissions::from_mode(0o700)).unwrap();
            assert!(result.is_ok(), "execute-only parent: {result:?}");
        }
        let mut file = files
            .resolve("album/disc/song.wav")
            .unwrap()
            .open_native_read()
            .unwrap();
        let mut data = Vec::new();
        file.read_to_end(&mut data).unwrap();
        assert_eq!(data, b"original");
        assert!(file.write_all(b"changed").is_err());
        for (target, link) in [
            ("album", "album-link"),
            ("album/disc/song.wav", "song-link.wav"),
            ("missing.wav", "dangling.wav"),
        ] {
            symlink(target, root.path().join(link)).unwrap();
        }
        for path in ["album-link/disc/song.wav", "song-link.wav", "dangling.wav"] {
            assert!(
                files
                    .resolve(path)
                    .unwrap()
                    .open_native_read()
                    .unwrap_err()
                    .to_string()
                    .contains("symlinks")
            );
        }
        assert_eq!(
            files
                .resolve("missing.wav")
                .unwrap()
                .open_native_read()
                .unwrap_err()
                .kind(),
            io::ErrorKind::NotFound
        );
        assert!(
            std::process::Command::new("mkfifo")
                .arg(root.path().join("pipe.wav"))
                .status()
                .unwrap()
                .success()
        );
        let _socket = UnixListener::bind(root.path().join("socket.wav")).unwrap();
        for path in ["pipe.wav", "socket.wav"] {
            assert!(
                files
                    .resolve(path)
                    .unwrap()
                    .open_native_read()
                    .unwrap_err()
                    .to_string()
                    .contains("special files")
            );
        }
        assert_eq!(
            std::fs::read(root.path().join("album/disc/song.wav")).unwrap(),
            b"original"
        );
    }

    #[test]
    fn exclusive_publication_preserves_racing_output_and_cleans_cancelled_stage() {
        let root = tempfile::tempdir().unwrap();
        let files = Arc::new(FileRegistry::default())
            .extension(root.path())
            .unwrap();
        let path = files.resolve("track.flac").unwrap();
        let mut stage = path.stage().unwrap();
        stage.file.write_all(b"new audio").unwrap();
        assert!(!path.absolute.exists());
        let error = stage
            .publish_new(&|| {
                // A different publisher creates the destination after the
                // planner's existence check but before the publication syscall.
                std::fs::write(&path.absolute, b"other publisher").unwrap();
                Ok(())
            })
            .unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::AlreadyExists);
        assert_eq!(std::fs::read(&path.absolute).unwrap(), b"other publisher");

        let cancelled = files.resolve("cancelled.flac").unwrap();
        let mut stage = cancelled.stage().unwrap();
        stage.file.write_all(b"cancelled audio").unwrap();
        assert_eq!(
            stage
                .publish_new(&|| Err("cancelled".into()))
                .unwrap_err()
                .to_string(),
            "cancelled"
        );
        assert!(!cancelled.absolute.exists());

        path.remove().unwrap();
        let mut stage = path.stage().unwrap();
        stage.file.write_all(b"complete audio").unwrap();
        stage.publish_new(&|| Ok(())).unwrap();
        assert_eq!(std::fs::read(&path.absolute).unwrap(), b"complete audio");
        assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 1);
    }

    #[cfg(unix)]
    #[test]
    fn stage_from_links_same_filesystem_source_and_survives_source_cleanup() {
        use cap_std::fs::MetadataExt;

        let root = tempfile::tempdir().unwrap();
        let files = Arc::new(FileRegistry::default())
            .extension(root.path())
            .unwrap();
        let source_path = files.resolve("source.bin").unwrap();
        std::fs::write(&source_path.absolute, b"source audio").unwrap();
        let source = source_path.open(OpenOptions::new().read(true)).unwrap();
        let destination = files.resolve("destination.bin").unwrap();
        let (stage, promoted) = destination.stage_from(&source_path, &source).unwrap();
        assert!(promoted);
        let source_metadata = source.metadata().unwrap();
        let stage_metadata = stage.file.metadata().unwrap();
        assert_eq!(source_metadata.dev(), stage_metadata.dev());
        assert_eq!(source_metadata.ino(), stage_metadata.ino());

        stage.publish_new(&|| Ok(())).unwrap();
        drop(source);
        source_path.remove().unwrap();
        assert_eq!(
            std::fs::read(&destination.absolute).unwrap(),
            b"source audio"
        );
        assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 1);
    }

    #[cfg(unix)]
    #[test]
    fn stage_from_copies_open_source_after_path_replacement() {
        let root = tempfile::tempdir().unwrap();
        let files = Arc::new(FileRegistry::default())
            .extension(root.path())
            .unwrap();
        let source_path = files.resolve("source.bin").unwrap();
        std::fs::write(&source_path.absolute, b"original audio").unwrap();
        let mut source = source_path.open(OpenOptions::new().read(true)).unwrap();
        std::fs::rename(&source_path.absolute, root.path().join("source.old")).unwrap();
        std::fs::write(&source_path.absolute, b"replacement audio").unwrap();
        let destination = files.resolve("destination.bin").unwrap();
        let (mut stage, promoted) = destination.stage_from(&source_path, &source).unwrap();
        assert!(!promoted);
        source.seek(SeekFrom::Start(0)).unwrap();
        std::io::copy(&mut source, &mut stage.file).unwrap();
        stage.publish_new(&|| Ok(())).unwrap();
        assert_eq!(
            std::fs::read(&destination.absolute).unwrap(),
            b"original audio"
        );
    }

    #[cfg(unix)]
    #[test]
    fn stage_from_copies_open_source_after_path_becomes_symlink() {
        use std::os::unix::fs::symlink;

        let root = tempfile::tempdir().unwrap();
        let files = Arc::new(FileRegistry::default())
            .extension(root.path())
            .unwrap();
        let source_path = files.resolve("source.bin").unwrap();
        std::fs::write(&source_path.absolute, b"original audio").unwrap();
        let mut source = source_path.open(OpenOptions::new().read(true)).unwrap();
        std::fs::rename(&source_path.absolute, root.path().join("source.old")).unwrap();
        symlink("source.old", &source_path.absolute).unwrap();
        let destination = files.resolve("destination.bin").unwrap();
        let (mut stage, promoted) = destination.stage_from(&source_path, &source).unwrap();
        assert!(!promoted);
        source.seek(SeekFrom::Start(0)).unwrap();
        std::io::copy(&mut source, &mut stage.file).unwrap();
        stage.publish_new(&|| Ok(())).unwrap();
        assert_eq!(
            std::fs::read(&destination.absolute).unwrap(),
            b"original audio"
        );
    }

    #[cfg(unix)]
    #[test]
    fn stage_from_preserves_existing_destination_and_cleans_cancelled_stage() {
        let root = tempfile::tempdir().unwrap();
        let files = Arc::new(FileRegistry::default())
            .extension(root.path())
            .unwrap();
        let source_path = files.resolve("source.bin").unwrap();
        std::fs::write(&source_path.absolute, b"source audio").unwrap();
        let source = source_path.open(OpenOptions::new().read(true)).unwrap();
        let destination = files.resolve("destination.bin").unwrap();
        std::fs::write(&destination.absolute, b"existing audio").unwrap();

        let (stage, promoted) = destination.stage_from(&source_path, &source).unwrap();
        assert!(promoted);
        let error = stage.publish_new(&|| Ok(())).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::AlreadyExists);
        assert_eq!(
            std::fs::read(&destination.absolute).unwrap(),
            b"existing audio"
        );
        assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 2);

        std::fs::remove_file(&destination.absolute).unwrap();
        let (stage, promoted) = destination.stage_from(&source_path, &source).unwrap();
        assert!(promoted);
        let error = stage.publish_new(&|| Err("cancelled".into())).unwrap_err();
        assert_eq!(error.to_string(), "cancelled");
        assert!(!destination.absolute.exists());
        assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 1);
    }
}
