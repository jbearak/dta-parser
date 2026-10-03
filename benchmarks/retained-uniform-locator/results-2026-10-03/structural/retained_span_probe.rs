//! Private, untimed instrumentation: exercise the actual owner methods and
//! exported spans. This does not claim public R ownership or CPU attribution.
use super::*;
use std::fmt::Write;

fn trace_word(hash: &mut u64, mut value: u64) {
    for _ in 0..8 {
        *hash ^= value & 255;
        *hash = hash.wrapping_mul(1099511628211);
        value >>= 8;
    }
}

unsafe fn raw(bytes: &[u8], kind: NumericKind, chunk: usize) -> Box<NumericData> {
    let p = dtatools_owned_numeric_from_raw(bytes.as_ptr(), bytes.len() / width(kind),
        chunk, kind as c_int, 0, 118, 0);
    assert!(!p.is_null());
    Box::from_raw(p.cast())
}

// Linear cumulative-end oracle, independent of partition_point. Check both
// region interfaces and scalar spans in nonmonotone order, with empty/end/error
// requests and complete bytes. Each chunk keeps its own physical base pointer.
unsafe fn check_apis(data: &NumericData) -> usize {
    let owner = &*data.native_owner.cast::<Owner>();
    let mut indices: Vec<usize> = (0..owner.length).rev().collect();
    indices.extend((0..owner.length).step_by(3));
    indices.extend([owner.length, owner.length.saturating_add(1), usize::MAX]);
    let mut checks = 0;
    for index in indices {
        let found = owner.chunks.iter().enumerate().find(|(_, chunk)| index < chunk.end);
        for requested in [0, 1, 9, usize::MAX] {
            let expected = if index > owner.length { None }
            else if index == owner.length || requested == 0 { Some((ptr::null(), 0)) }
            else {
                let (i, chunk) = found.unwrap();
                let first = if i == 0 { 0 } else { owner.chunks[i-1].end };
                Some((chunk.pointer().add((index-first)*owner.width), requested.min(chunk.end-index)))
            };
            assert_eq!(owner.region(index, requested), expected);
            let mut pointer = 1usize as *const c_void;
            let mut count = usize::MAX;
            let status = dtatools_owned_numeric_region((data as *const NumericData).cast(),
                index, requested, &mut pointer, &mut count);
            assert_eq!(status, i32::from(expected.is_some()));
            let expected = expected.unwrap_or((ptr::null(), 0));
            assert_eq!((pointer.cast::<u8>(), count), expected);
            if count != 0 {
                assert_eq!(std::slice::from_raw_parts(pointer.cast::<u8>(), count*owner.width),
                           std::slice::from_raw_parts(expected.0, count*owner.width));
            }
            checks += 2;
        }
        let mut pointer = 1usize as *const c_void;
        let (mut start, mut end) = (usize::MAX, usize::MAX);
        let status = dtatools_owned_numeric_scalar_span((data as *const NumericData).cast(),
            index, &mut pointer, &mut start, &mut end);
        if let Some((i, chunk)) = found {
            assert_eq!(status, 1);
            assert_eq!(pointer.cast::<u8>(), chunk.pointer());
            assert_eq!(start, if i == 0 { 0 } else { owner.chunks[i-1].end });
            assert_eq!(end, chunk.end);
        } else {
            assert_eq!((status, pointer, start, end), (0, ptr::null(), 0, 0));
        }
        checks += 1;
    }
    checks
}

#[test]
fn retained_span_work_probe() {
    let output = std::env::var("DTATOOLS_SPAN_PROBE_OUTPUT").expect("private output path");
    let mut api_checks = 0;
    for kind in [NumericKind::Byte, NumericKind::Int, NumericKind::Long, NumericKind::Float] {
        for length in [0, 1, 2, 3, 7, 8, 17] {
            let bytes: Vec<u8> = (0..length*width(kind)).map(|i| (i%251) as u8).collect();
            for chunk in [1, 3, 7, 19] {
                let data = unsafe { raw(&bytes, kind, chunk) };
                api_checks += unsafe { check_apis(&data) };
            }
        }
    }
    // Slices share an allocation but are shuffled and separated physically.
    // Stored row lengths may be uniform or irregular; empty arrays are skipped.
    let base = Int16Array::from((0..80_i16).collect::<Vec<_>>());
    for lengths in [[7,7,3], [3,7,7], [7,2,9]] {
        let mut arrays: Vec<ArrayRef> = vec![Arc::new(Int16Array::from(Vec::<i16>::new()))];
        for (offset, length) in [40,2,20].into_iter().zip(lengths) {
            arrays.push(Arc::new(base.slice(offset, length)));
            arrays.push(Arc::new(Int16Array::from(Vec::<i16>::new())));
        }
        let data = prepare_from_arrow(&arrays, NumericKind::Int, TemporalKind::None,
            FormatVersion::V118, lengths.iter().sum(), || false).unwrap().into_descriptor();
        api_checks += unsafe { check_apis(&data) };
    }

    let mut csv = String::from("length,long_chunk,float_chunk,reverse,span_calls,search_comparisons,span_trace\n");
    let mut cases = Vec::new();
    for reverse in [false,true] {
        for (x,y) in [(0,0),(8191,16385),(7,11)] { cases.push((1_000_000,x,y,reverse)); }
        for n in [16383,16384,16385] { cases.push((n,7,11,reverse)); }
    }
    let mut red = 0;
    for (length, xchunk, ychunk, reverse) in cases {
        let xbytes = vec![0u8;length*4];
        let ybytes = vec![0u8;length*4];
        // Plain C spans do not call Rust. Build owners only for retained pairs.
        let owners = if xchunk != 0 { Some(unsafe {
            (raw(&xbytes,NumericKind::Long,xchunk),raw(&ybytes,NumericKind::Float,ychunk))
        }) } else { None };
        CHUNK_SEARCH_COMPARISONS.with(|count| count.set(0));
        let (mut row, mut calls, mut trace) = (0usize,0usize,14695981039346656037u64);
        while row < length {
            let mut count = (length-row).min(16384);
            for side in if reverse { [1,0] } else { [0,1] } {
                let requested = count;
                if let Some((x,y)) = &owners {
                    let data = if side == 0 { x.as_ref() } else { y.as_ref() };
                    let mut pointer = ptr::null();
                    assert_eq!(unsafe { dtatools_owned_numeric_region((data as *const NumericData).cast(),
                        row, requested, &mut pointer, &mut count) },1);
                    let chunk = if side == 0 { xchunk } else { ychunk };
                    assert_eq!(count, requested.min(chunk-row%chunk));
                    let bytes = if side == 0 { &xbytes } else { &ybytes };
                    assert_eq!(pointer.cast::<u8>(),unsafe { bytes.as_ptr().add(row*4) });
                }
                for word in [if side == 0 {2} else {3},row,requested,count] {
                    trace_word(&mut trace, word as u64);
                }
                calls += 1;
            }
            row += count;
        }
        let comparisons = CHUNK_SEARCH_COMPARISONS.with(|count| count.get());
        if xchunk != 0 && comparisons != 0 { red += 1; }
        writeln!(csv,"{length},{xchunk},{ychunk},{},{calls},{comparisons},{trace:016x}",u8::from(reverse)).unwrap();
    }
    std::fs::write(&output,csv).unwrap();
    eprintln!("retained span probe: {api_checks} API checks passed, {red} uniform search-work failures");
    if std::env::var_os("DTATOOLS_REQUIRE_UNIFORM_LOOKUP").is_some() {
        assert_eq!(red,0,"uniform lookup still performs binary-search comparisons");
    }
}
