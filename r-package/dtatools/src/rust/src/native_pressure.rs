//! Amortize R collections requested for allocations outside R's heap.

use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

const LIVE_BYTE_LIMIT: usize = 64 * 1024 * 1024;
// Require substantial new allocation before another attempt even when the
// previously collected buffers remain reachable. Half the pressure limit
// retains headroom for the existing repeated-large-read memory bound.
const ALLOCATION_BUDGET: usize = LIVE_BYTE_LIMIT / 2;

pub(crate) struct NativeMemoryPressure {
    debt: AtomicUsize,
    collecting: AtomicBool,
    attempts: AtomicUsize,
}

fn saturating_add(counter: &AtomicUsize, amount: usize) {
    if amount != 0 {
        let _ = counter.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
            Some(value.saturating_add(amount))
        });
    }
}

impl NativeMemoryPressure {
    pub(crate) const fn new() -> Self {
        Self {
            debt: AtomicUsize::new(0),
            collecting: AtomicBool::new(false),
            attempts: AtomicUsize::new(0),
        }
    }

    pub(crate) fn allocated(&self, bytes: usize) {
        saturating_add(&self.debt, bytes);
    }

    pub(crate) fn debt(&self) -> usize {
        self.debt.load(Ordering::Relaxed)
    }

    pub(crate) fn attempts(&self) -> usize {
        self.attempts.load(Ordering::Relaxed)
    }

    /// `collect` runs on the R thread through the C boundary that contains R
    /// nonlocal exits. No lock or Rust borrow guard is held across callbacks.
    /// Allocations made by finalizers stay in the new debt counter. A failed
    /// attempt or Rust unwind restores the claimed debt before admitting retry.
    pub(crate) fn collect_if_needed<E>(
        &self,
        live_bytes: usize,
        collect: impl FnOnce() -> Result<(), E>,
    ) -> Result<bool, E> {
        if live_bytes <= LIVE_BYTE_LIMIT
            || self.debt() <= ALLOCATION_BUDGET
            || self
                .collecting
                .compare_exchange(false, true, Ordering::Acquire, Ordering::Relaxed)
                .is_err()
        {
            return Ok(false);
        }
        let mut attempt = CollectionAttempt {
            pressure: self,
            claimed: self.debt.swap(0, Ordering::Relaxed),
            succeeded: false,
        };
        // A preceding caller may have consumed the debt between our first
        // inspection and claiming the flag. Return partial new debt unchanged.
        if attempt.claimed <= ALLOCATION_BUDGET {
            return Ok(false);
        }
        saturating_add(&self.attempts, 1);
        collect()?;
        attempt.succeeded = true;
        Ok(true)
    }
}

struct CollectionAttempt<'a> {
    pressure: &'a NativeMemoryPressure,
    claimed: usize,
    succeeded: bool,
}

impl Drop for CollectionAttempt<'_> {
    fn drop(&mut self) {
        if !self.succeeded {
            self.pressure.allocated(self.claimed);
        }
        self.pressure.collecting.store(false, Ordering::Release);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn collect(pressure: &NativeMemoryPressure, live: usize) -> bool {
        pressure
            .collect_if_needed(live, || Ok::<(), ()>(()))
            .unwrap()
    }

    #[test]
    fn live_buffers_do_not_force_repeated_collection() {
        let pressure = NativeMemoryPressure::new();
        pressure.allocated(LIVE_BYTE_LIMIT + 1);
        assert!(collect(&pressure, LIVE_BYTE_LIMIT + 1));
        for _ in 0..100 {
            pressure.allocated(8);
            assert!(!collect(&pressure, LIVE_BYTE_LIMIT + 801));
        }
        assert_eq!(pressure.attempts(), 1);
        assert_eq!(pressure.debt(), 800);
        pressure.allocated(ALLOCATION_BUDGET);
        assert!(collect(&pressure, LIVE_BYTE_LIMIT + ALLOCATION_BUDGET));
        assert_eq!(pressure.attempts(), 2);
    }

    #[test]
    fn both_live_storage_and_new_allocation_are_required() {
        let pressure = NativeMemoryPressure::new();
        pressure.allocated(ALLOCATION_BUDGET);
        assert!(!collect(&pressure, LIVE_BYTE_LIMIT + 1));
        pressure.allocated(1);
        assert!(!collect(&pressure, LIVE_BYTE_LIMIT));
        assert_eq!(pressure.debt(), ALLOCATION_BUDGET + 1);
        assert_eq!(pressure.attempts(), 0);
        assert!(collect(&pressure, LIVE_BYTE_LIMIT + 1));
        pressure.allocated(0);
        assert_eq!(pressure.debt(), 0);
    }

    #[test]
    fn finalizer_allocations_survive_success_and_nested_reads_do_not_collect() {
        let pressure = NativeMemoryPressure::new();
        pressure.allocated(LIVE_BYTE_LIMIT);
        assert!(pressure
            .collect_if_needed(LIVE_BYTE_LIMIT + 1, || {
                pressure.allocated(ALLOCATION_BUDGET + 1);
                assert!(!collect(&pressure, LIVE_BYTE_LIMIT * 2));
                Ok::<(), ()>(())
            })
            .unwrap());
        assert_eq!(pressure.debt(), ALLOCATION_BUDGET + 1);
        assert!(collect(&pressure, LIVE_BYTE_LIMIT + 1));
    }

    #[test]
    fn failed_collections_restore_old_and_reentrant_allocation_debt() {
        let pressure = NativeMemoryPressure::new();
        pressure.allocated(LIVE_BYTE_LIMIT);
        let result = pressure.collect_if_needed(LIVE_BYTE_LIMIT + 1, || {
            pressure.allocated(17);
            Err("collection failed")
        });
        assert_eq!(result, Err("collection failed"));
        assert_eq!(pressure.debt(), LIVE_BYTE_LIMIT + 17);
        assert!(collect(&pressure, LIVE_BYTE_LIMIT + 1));
    }

    #[test]
    fn unwinding_releases_the_attempt_and_restores_debt() {
        let pressure = NativeMemoryPressure::new();
        pressure.allocated(LIVE_BYTE_LIMIT);
        let result = std::panic::catch_unwind(|| {
            let _: Result<bool, ()> =
                pressure.collect_if_needed(LIVE_BYTE_LIMIT + 1, || panic!("collector panic"));
        });
        assert!(result.is_err());
        assert_eq!(pressure.debt(), LIVE_BYTE_LIMIT);
        assert!(collect(&pressure, LIVE_BYTE_LIMIT + 1));
    }

    #[test]
    fn allocation_debt_saturates_without_losing_retry_or_new_allocations() {
        let pressure = NativeMemoryPressure::new();
        pressure.allocated(usize::MAX);
        pressure.allocated(1);
        assert_eq!(pressure.debt(), usize::MAX);
        let result = pressure.collect_if_needed(LIVE_BYTE_LIMIT + 1, || {
            pressure.allocated(10);
            Err(())
        });
        assert_eq!(result, Err(()));
        assert_eq!(pressure.debt(), usize::MAX);
        assert!(pressure
            .collect_if_needed(LIVE_BYTE_LIMIT + 1, || {
                pressure.allocated(11);
                Ok::<(), ()>(())
            })
            .unwrap());
        assert_eq!(pressure.debt(), 11);
    }
}
