use crate::error::{Error, Result};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};

/// Random access to the bytes of a `.dta` file.
///
/// The reader asks only for the ranges it needs, so a source can be a
/// file of any size, a byte slice, or a callback into JavaScript.
#[allow(clippy::len_without_is_empty)]
pub trait Source {
    /// The file's length in bytes.
    fn len(&self) -> u64;

    /// Fill `buf` with the bytes starting at `offset`. Asking for bytes
    /// past the end is an error.
    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> Result<()>;

    /// The same bytes through `&self`, for reads from several threads at
    /// once; `None` (the default) when the source cannot do that, and the
    /// reader then reads on one thread.
    fn shared(&self) -> Option<&dyn SharedSource> {
        None
    }
}

/// A source several threads may read at once.
pub trait SharedSource: Sync {
    /// As [`Source::read_at`]. It must not change what `read_at` reads
    /// next.
    fn read_at_shared(&self, offset: u64, buf: &mut [u8]) -> Result<()>;
}

/// A file in memory.
pub struct Bytes<T: AsRef<[u8]>>(pub T);

impl<T: AsRef<[u8]> + Sync> Source for Bytes<T> {
    fn len(&self) -> u64 {
        self.0.as_ref().len() as u64
    }

    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> Result<()> {
        self.read_at_shared(offset, buf)
    }

    fn shared(&self) -> Option<&dyn SharedSource> {
        Some(self)
    }
}

impl<T: AsRef<[u8]> + Sync> SharedSource for Bytes<T> {
    fn read_at_shared(&self, offset: u64, buf: &mut [u8]) -> Result<()> {
        let data = self.0.as_ref();
        let start = usize::try_from(offset).ok().filter(|&s| s <= data.len());
        match start.and_then(|s| data.get(s..s + buf.len())) {
            Some(bytes) => {
                buf.copy_from_slice(bytes);
                Ok(())
            }
            None => Err(Error::at(offset, "unexpected end of file")),
        }
    }
}

/// A file on disk.
pub struct FileSource {
    file: File,
    len: u64,
    position: u64,
}

impl FileSource {
    pub fn open(path: impl AsRef<std::path::Path>) -> Result<Self> {
        let file = File::open(path)?;
        let len = file.metadata()?.len();
        Ok(FileSource { file, len, position: 0 })
    }
}

impl Source for FileSource {
    fn len(&self) -> u64 {
        self.len
    }

    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> Result<()> {
        if offset.checked_add(buf.len() as u64).is_none_or(|end| end > self.len) {
            return Err(Error::at(offset, "unexpected end of file"));
        }
        // Sequential reads (the common case) skip the seek.
        if offset != self.position {
            self.file.seek(SeekFrom::Start(offset))?;
        }
        self.file.read_exact(buf)?;
        self.position = offset + buf.len() as u64;
        Ok(())
    }

    #[cfg(unix)]
    fn shared(&self) -> Option<&dyn SharedSource> {
        Some(self)
    }
}

/// Positional reads, which leave the file position (and so `position`)
/// alone. Windows' `seek_read` moves it, so Windows reads on one thread.
#[cfg(unix)]
impl SharedSource for FileSource {
    fn read_at_shared(&self, offset: u64, buf: &mut [u8]) -> Result<()> {
        use std::os::unix::fs::FileExt;
        if offset.checked_add(buf.len() as u64).is_none_or(|end| end > self.len) {
            return Err(Error::at(offset, "unexpected end of file"));
        }
        // read_exact_at retries short and interrupted reads.
        self.file.read_exact_at(buf, offset)?;
        Ok(())
    }
}

/// Read `len` bytes at `offset` into a new buffer, after checking that
/// they lie inside the file, so a corrupt length cannot make us
/// allocate more than the file holds.
pub(crate) fn read_vec<S: Source + ?Sized>(src: &mut S, offset: u64, len: u64) -> Result<Vec<u8>> {
    if offset.checked_add(len).is_none_or(|end| end > src.len()) {
        return Err(Error::at(offset, "unexpected end of file"));
    }
    let mut buf = vec![0; len as usize];
    src.read_at(offset, &mut buf)?;
    Ok(buf)
}
