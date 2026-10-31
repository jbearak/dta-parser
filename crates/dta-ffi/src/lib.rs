//! C ABIs over the dta crate. On wasm32, the one the npm package's
//! module exports (`wasm.rs`); on other targets, a native one for Julia
//! (`native.rs`, declared in `include/dta.h`). Both use `json.rs`.

mod json;

// Used by the wasm module; built everywhere so its tests run natively.
#[cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]
mod strings;

#[cfg(target_arch = "wasm32")]
mod wasm;

#[cfg(not(target_arch = "wasm32"))]
pub mod native;
