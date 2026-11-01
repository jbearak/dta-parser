//! How many threads a read or write may use (plan 0007).
//!
//! The default is at most three: on an M4 Max, every read and write
//! measured from R, Python and Rust kept its CPU time within 1.15× of
//! the same task on one thread at three threads, and Python's full read
//! of a 4.8 GB file did not at four (memory bandwidth shared by more
//! cores makes each do its work more slowly). On x86, hardware threads
//! usually come in SMT pairs that add little, so half of them count.
//! wasm has no threads.

/// The number of worker threads for a task asked to use `requested`
/// (0 for the default): `requested` if given, else `DTA_THREADS` if it
/// holds a positive number, else the default; never more than the
/// machine has, and always 1 in wasm.
pub fn resolve(requested: usize) -> usize {
    if cfg!(target_arch = "wasm32") {
        return 1;
    }
    let available = std::thread::available_parallelism().map_or(1, |n| n.get());
    let wanted = if requested > 0 {
        requested
    } else {
        match std::env::var("DTA_THREADS").ok().and_then(|v| v.trim().parse::<usize>().ok()) {
            Some(n) if n > 0 => n,
            _ => default(available),
        }
    };
    wanted.min(available).max(1)
}

fn default(available: usize) -> usize {
    let cores = if cfg!(any(target_arch = "x86", target_arch = "x86_64")) { (available / 2).max(1) } else { available };
    cores.min(3)
}

/// Whether `DTA_TEST_SMALL_CHUNKS=1`: the bindings' tests set it to
/// run small files through the parallel paths.
pub(crate) fn small_for_tests() -> bool {
    std::env::var("DTA_TEST_SMALL_CHUNKS").is_ok_and(|v| v == "1")
}

/// A panic's message, for an error.
pub(crate) fn panic_message(payload: &(dyn std::any::Any + Send)) -> String {
    payload
        .downcast_ref::<&str>()
        .map(|s| s.to_string())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "unknown panic".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_default_is_small() {
        assert_eq!(default(1), 1);
        assert_eq!(default(16), 3);
        assert_eq!(default(2), if cfg!(any(target_arch = "x86", target_arch = "x86_64")) { 1 } else { 2 });
        assert!(resolve(1) == 1);
        assert!(resolve(10_000) >= 1);
    }
}
