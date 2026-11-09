//! Columns for datakit (plan 0019, and plan 0024's stage 4): Parquet and
//! `.dta` reads into buffers that numpy adopts without a copy, and
//! writes from numpy arrays, through the Arrow layouts the readers and
//! writers share. These functions are internal to dta_parser and
//! versioned by `ABI_VERSION`; datakit is their only caller.

pub(crate) mod dta;
pub(crate) mod ffi;
pub(crate) mod frame;
pub(crate) mod read;
pub(crate) mod write;

/// The version of the functions datakit calls; datakit checks it when it
/// loads. Raise it when any of them changes what it takes or gives.
pub const ABI_VERSION: u32 = 2;
