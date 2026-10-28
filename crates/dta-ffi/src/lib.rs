//! The C ABI the npm package's wasm module exports (`wasm.rs`).

#[cfg(target_arch = "wasm32")]
mod json;

#[cfg(target_arch = "wasm32")]
mod wasm;
