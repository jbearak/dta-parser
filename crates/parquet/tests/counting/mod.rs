//! An allocator that records the largest single allocation a thread asks
//! for while [`largest_during`] runs, so tests can check that hostile
//! files cannot make the reader ask for absurd amounts of memory.
#![allow(dead_code)]

use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;

pub struct Counting;

thread_local! {
    static TRACK: Cell<bool> = const { Cell::new(false) };
    static LARGEST: Cell<usize> = const { Cell::new(0) };
}

fn note(n: usize) {
    let _ = TRACK.try_with(|t| {
        if t.get() {
            let _ = LARGEST.try_with(|m| m.set(m.get().max(n)));
        }
    });
}

unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        note(layout.size());
        System.alloc(layout)
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        note(layout.size());
        System.alloc_zeroed(layout)
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        note(new_size);
        System.realloc(ptr, layout, new_size)
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        System.dealloc(ptr, layout)
    }
}

/// Run `f`, returning its result and the largest allocation it asked
/// for on this thread.
pub fn largest_during<R>(f: impl FnOnce() -> R) -> (R, usize) {
    LARGEST.with(|m| m.set(0));
    TRACK.with(|t| t.set(true));
    let r = f();
    TRACK.with(|t| t.set(false));
    (r, LARGEST.with(Cell::get))
}
