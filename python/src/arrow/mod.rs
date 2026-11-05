//! Arrow memory for datakit (plan 0019): reads that polars adopts without
//! a copy, writes from polars' own export, the digests of finished
//! columns, and `.dta` files read and written through the same buffers.
//! These functions are internal to dta_parser and versioned by
//! `ABI_VERSION`; datakit is their only caller.

pub(crate) mod digest;
pub(crate) mod ffi;
pub(crate) mod read;
pub(crate) mod write;

/// The version of the functions datakit calls; datakit checks it when it
/// loads. Raise it when any of them changes what it takes or gives.
pub const ABI_VERSION: u32 = 1;
