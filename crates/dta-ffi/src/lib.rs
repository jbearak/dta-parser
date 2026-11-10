//! The C ABI over the dta crate that the npm package's wasm module
//! exports (`wasm.rs`, over `wasm_common.rs`), with `json.rs` and
//! `strings.rs`, which are built on every target so their tests run
//! natively.

#[cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]
mod json;

// Used by the wasm module; built everywhere so its tests run natively.
#[cfg_attr(not(all(target_arch = "wasm32", feature = "wasm-dta")), allow(dead_code))]
mod strings;

#[cfg(target_arch = "wasm32")]
mod wasm_common;

#[cfg(all(target_arch = "wasm32", feature = "wasm-dta"))]
mod wasm;
