//! Fixed-width text through a SAS setup file, into a `.dta` file, for
//! datakit's module (feature `wasm-parquet`). JavaScript puts the setup
//! files and the data in module memory (the data straight from the file,
//! with no JavaScript copy) and takes the `.dta` bytes through
//! `host_write` as they are written.

use crate::json;
use crate::wasm_common::{call, result, Fail, HostSink, State};

/// Convert `data` as the setup files describe it and write the release
/// 118 file to host sink `sink`. The `n_setups` setups lie end to end at
/// `setups`, the `k`th ending at `setup_ends[k]`. `recodes` is 0 for
/// "setup", 1 "tagged", 2 "none"; `commented_formats` 0 or 1. Returns
/// the warnings as a JSON array of strings, or null on failure.
///
/// # Safety
/// The pointers hold the stated lengths.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn dta_fixed_width(
    setups: *const u8,
    setups_len: usize,
    setup_ends: *const u32,
    n_setups: usize,
    data: *const u8,
    data_len: usize,
    recodes: u32,
    commented_formats: u32,
    sink: u32,
) -> *const u8 {
    call(std::ptr::null(), |state: &mut State| {
        if n_setups == 0 {
            return Err("no setup file was given".into());
        }
        let mode = match recodes {
            0 => dta::Recodes::Setup,
            1 => dta::Recodes::Tagged,
            2 => dta::Recodes::None,
            _ => return Err("recodes must be \"setup\", \"tagged\" or \"none\"".into()),
        };
        let all = if setups_len == 0 { &[][..] } else { std::slice::from_raw_parts(setups, setups_len) };
        let ends = std::slice::from_raw_parts(setup_ends, n_setups);
        let mut parts: Vec<&[u8]> = Vec::with_capacity(n_setups);
        let mut from = 0usize;
        for &end in ends {
            let part = all.get(from..end as usize).ok_or("setup offsets out of order")?;
            parts.push(part);
            from = end as usize;
        }
        let data = if data_len == 0 { &[][..] } else { std::slice::from_raw_parts(data, data_len) };
        let warnings = dta::fixed_width_to_dta(&parts, data, mode, commented_formats != 0, HostSink(sink)).map_err(Fail::from)?;
        let messages: Vec<String> = warnings.into_iter().map(|w| w.message).collect();
        Ok(result(state, json::strings(&messages).into_bytes()))
    })
}
