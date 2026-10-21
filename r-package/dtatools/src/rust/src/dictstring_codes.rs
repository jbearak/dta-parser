//! Integer codes that let two dictionary-string columns match by equality
//! without making an R string for each value.

use ahash::AHashMap;
use std::ffi::{c_char, c_int, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};

/// Borrow one dictionary value's UTF-8 bytes through the accessor that the
/// C readers use, whatever layout the payload keeps its dictionary in.
unsafe fn value_bytes<'a>(data: *mut c_void, id: u32) -> Option<&'a [u8]> {
    let mut bytes: *const c_char = std::ptr::null();
    let mut length: c_int = 0;
    if crate::dtatools_dictstring_bytes(data, id, &mut bytes, &mut length) == 0
        || bytes.is_null()
        || length < 0
    {
        return None;
    }
    Some(std::slice::from_raw_parts(
        bytes.cast::<u8>(),
        length as usize,
    ))
}

/// Why a side's rows got no codes.
enum Refusal {
    /// An id has no value, or the codes overflow `int`.
    Invalid,
    /// A row's value holds a NUL byte, which an R string cannot.
    Nul,
}

/// Code one side's rows. Each distinct id is looked up once; `table` keeps
/// its code, and zero marks an id not yet seen.
unsafe fn code_rows<'a>(
    data: *mut c_void,
    ids: &[u32],
    table: &mut [c_int],
    codes: &mut AHashMap<&'a [u8], c_int>,
    output: &mut [c_int],
) -> Result<(), Refusal> {
    for (slot, &id) in output.iter_mut().zip(ids) {
        let entry = table.get_mut(id as usize).ok_or(Refusal::Invalid)?;
        if *entry == 0 {
            let bytes = value_bytes(data, id).ok_or(Refusal::Invalid)?;
            if bytes.contains(&0) {
                return Err(Refusal::Nul);
            }
            let next = c_int::try_from(codes.len())
                .ok()
                .and_then(|count| count.checked_add(1))
                .ok_or(Refusal::Invalid)?;
            *entry = *codes.entry(bytes).or_insert(next);
        }
        *slot = *entry;
    }
    Ok(())
}

#[no_mangle]
/// Give each row of two dictionary-string columns a positive integer code.
/// Two rows, on either side, share a code exactly when their values have
/// equal bytes. Codes count from one in order of first appearance, `y`
/// first. Returns 1 when every row has a code, 2 when a row's value holds a
/// NUL byte, and 0 when an id has no value or the codes overflow `int`.
///
/// # Safety
///
/// `x` and `y` must point to live `DictStringData` payloads whose
/// dictionaries hold `x_cardinality` and `y_cardinality` values and stay
/// live until this call returns. `x_ids` and `y_ids` must hold `x_length`
/// and `y_length` readable ids, and `x_codes` and `y_codes` that many
/// writable `int`s.
pub unsafe extern "C" fn dtatools_dictstring_match_codes(
    x: *mut c_void,
    x_cardinality: usize,
    x_ids: *const u32,
    x_length: usize,
    x_codes: *mut c_int,
    y: *mut c_void,
    y_cardinality: usize,
    y_ids: *const u32,
    y_length: usize,
    y_codes: *mut c_int,
) -> c_int {
    let call = || -> Result<(), Refusal> {
        if x.is_null() || y.is_null() {
            return Err(Refusal::Invalid);
        }
        let slice = |ids: *const u32, length: usize| {
            if length == 0 {
                Some(&[][..])
            } else if ids.is_null() {
                None
            } else {
                Some(unsafe { std::slice::from_raw_parts(ids, length) })
            }
        };
        let output = |codes: *mut c_int, length: usize| {
            if length == 0 {
                Some(&mut [][..])
            } else if codes.is_null() {
                None
            } else {
                Some(unsafe { std::slice::from_raw_parts_mut(codes, length) })
            }
        };
        let (x_ids, y_ids) = (slice(x_ids, x_length), slice(y_ids, y_length));
        let (x_codes, y_codes) = (output(x_codes, x_length), output(y_codes, y_length));
        let (Some(x_ids), Some(y_ids), Some(x_codes), Some(y_codes)) =
            (x_ids, y_ids, x_codes, y_codes)
        else {
            return Err(Refusal::Invalid);
        };
        let mut x_table = vec![0; x_cardinality];
        let mut y_table = vec![0; y_cardinality];
        let mut codes = AHashMap::with_capacity(y_cardinality.min(y_length));
        unsafe {
            code_rows(y, y_ids, &mut y_table, &mut codes, y_codes)?;
            code_rows(x, x_ids, &mut x_table, &mut codes, x_codes)?;
        }
        Ok(())
    };
    match catch_unwind(AssertUnwindSafe(call)) {
        Ok(Ok(())) => 1,
        Ok(Err(Refusal::Nul)) => 2,
        Ok(Err(Refusal::Invalid)) | Err(_) => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::dtatools_dictstring_match_codes;
    use crate::{dtatools_dictstring_free, DictStringData};
    use ahash::AHashMap;
    use std::ffi::{c_int, c_void};
    use std::ptr;

    fn payload(values: &[&str], ids: Vec<u32>) -> *mut c_void {
        let mut dictionary = AHashMap::new();
        for (id, value) in values.iter().enumerate() {
            dictionary.insert((*value).to_owned(), id as u32);
        }
        let mut views = vec![(ptr::null(), 0); dictionary.len()];
        for (value, &id) in &dictionary {
            views[id as usize] = (value.as_ptr(), value.len());
        }
        Box::into_raw(Box::new(DictStringData::new(ids, dictionary, views))).cast()
    }

    unsafe fn codes(
        x: *mut c_void,
        x_ids: &[u32],
        y: *mut c_void,
        y_ids: &[u32],
        cardinality: (usize, usize),
    ) -> Result<(Vec<c_int>, Vec<c_int>), c_int> {
        let mut x_codes = vec![0; x_ids.len()];
        let mut y_codes = vec![0; y_ids.len()];
        let status = dtatools_dictstring_match_codes(
            x,
            cardinality.0,
            x_ids.as_ptr(),
            x_ids.len(),
            x_codes.as_mut_ptr(),
            y,
            cardinality.1,
            y_ids.as_ptr(),
            y_ids.len(),
            y_codes.as_mut_ptr(),
        );
        if status == 1 {
            Ok((x_codes, y_codes))
        } else {
            Err(status)
        }
    }

    #[test]
    fn codes_are_equal_exactly_when_bytes_are() {
        let x_values = ["b", "", "\u{e9}", "only x", "a"];
        let y_values = ["a", "only y", "\u{e9}", ""];
        let x_ids = vec![0, 1, 2, 4, 0, 3, 4, 1];
        let y_ids = vec![0, 2, 1, 3, 0];
        let x = payload(&x_values, x_ids.clone());
        let y = payload(&y_values, y_ids.clone());
        let (x_codes, y_codes) = unsafe { codes(x, &x_ids, y, &y_ids, (5, 4)) }.unwrap();
        let text: Vec<&str> = x_ids
            .iter()
            .map(|&id| x_values[id as usize])
            .chain(y_ids.iter().map(|&id| y_values[id as usize]))
            .collect();
        let joined: Vec<c_int> = x_codes.iter().chain(&y_codes).copied().collect();
        for left in 0..text.len() {
            assert!(joined[left] > 0);
            for right in 0..text.len() {
                assert_eq!(text[left] == text[right], joined[left] == joined[right]);
            }
        }
        // Codes count from one in order of first appearance, y first.
        assert_eq!(y_codes, vec![1, 2, 3, 4, 1]);
        let (empty_x, empty_y) = unsafe { codes(x, &[], y, &[], (5, 4)) }.unwrap();
        assert!(empty_x.is_empty() && empty_y.is_empty());
        // An id outside the dictionary fails rather than reading past it.
        assert_eq!(unsafe { codes(x, &[5], y, &y_ids, (5, 4)) }, Err(0));
        assert_eq!(unsafe { codes(x, &[0], y, &y_ids, (5, 3)) }, Err(0));
        // A NUL byte refuses only when a row uses that value.
        let nul = payload(&["a", "b\0c"], vec![0, 1]);
        assert!(unsafe { codes(nul, &[0, 0], y, &y_ids, (2, 4)) }.is_ok());
        assert_eq!(unsafe { codes(nul, &[0, 1], y, &y_ids, (2, 4)) }, Err(2));
        assert_eq!(unsafe { codes(x, &x_ids, nul, &[1], (5, 2)) }, Err(2));
        unsafe {
            dtatools_dictstring_free(x);
            dtatools_dictstring_free(y);
            dtatools_dictstring_free(nul);
        }
    }
}
