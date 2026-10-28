//! Read and write Stata `.dta` files.
//!
//! The crate does no I/O of its own: readers take a [`Source`] and the
//! writer a [`Sink`], so the same code serves files on disk (R) and byte
//! ranges supplied by JavaScript (wasm).
