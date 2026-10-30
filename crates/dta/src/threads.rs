//! How many threads a read or write may use (plan 0007).
//!
//! The default is at most four, which on the machines measured kept a
//! parallel task's CPU time within 1.15× of the same task on one
//! thread. On x86, hardware threads usually come in SMT pairs that add
//! little, so half of them count. wasm has no threads.

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
    cores.min(4)
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
        assert!(default(16) <= 4);
        assert!(resolve(1) == 1);
        assert!(resolve(10_000) >= 1);
    }
}
