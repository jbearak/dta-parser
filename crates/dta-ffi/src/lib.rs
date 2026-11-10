//! The C ABI over the dta crate that the npm packages' wasm modules
//! export (`wasm.rs`, `parquet_wasm.rs`, `fixed_width_wasm.rs`), with
//! `json.rs` and `strings.rs`, which are built on every target so their
//! tests run natively.

#[cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]
mod json;

// Used by the wasm modules; built everywhere so its tests run natively.
// Each module uses part of it.
#[cfg_attr(not(all(target_arch = "wasm32", feature = "wasm-dta", feature = "wasm-parquet")), allow(dead_code))]
mod strings;

// Two wasm modules (plan 0021): `wasm-dta` for @jbearak/dta-parser,
// `wasm-parquet` (Parquet and fixed-width text) for @jbearak/datakit.
#[cfg(target_arch = "wasm32")]
mod wasm_common;

#[cfg(all(target_arch = "wasm32", feature = "wasm-dta"))]
mod wasm;

#[cfg(all(target_arch = "wasm32", feature = "wasm-parquet"))]
mod parquet_wasm;

#[cfg(all(target_arch = "wasm32", feature = "wasm-parquet"))]
mod fixed_width_wasm;
