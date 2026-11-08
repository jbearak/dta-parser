//! C ABIs over the dta crate. On wasm32, the one the npm package's
//! modules export (`wasm.rs`, `parquet_wasm.rs`); on other targets, a native one for Julia
//! (`native.rs`, declared in `include/dta.h`). Both use `json.rs`.

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

#[cfg(not(target_arch = "wasm32"))]
pub mod native;

#[cfg(not(target_arch = "wasm32"))]
pub mod parquet_native;
