//! The Arrow C stream by hand (plan 0025, stage 2b): a table exported
//! and imported again gives the same buffers, and an imported stream is
//! released once, whatever happens, with every batch freed.

use std::ffi::{c_char, c_int, c_void};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use dta_arrow::ffi::{
    export_stream, import_stream, metadata, text_at, valid, Array, ArrayRef, ArrowArray, ArrowArrayStream, ArrowSchema,
    Field, InField, Owner, Table, DICTIONARY_ORDERED,
};

/// The buffers the exported arrays point into.
struct Buffers {
    ints: Vec<i64>,
    ints_valid: Vec<u8>,
    offsets: Vec<i32>,
    bytes: Vec<u8>,
    codes: Vec<i8>,
    levels_offsets: Vec<i32>,
    levels_bytes: Vec<u8>,
}

fn buffers() -> Buffers {
    Buffers {
        ints: vec![10, 0, -3, 7, 1 << 40],
        // Row 1 is null.
        ints_valid: vec![0b1_1101],
        offsets: vec![0, 3, 3, 8, 9, 13],
        bytes: b"abcdefghijklm".to_vec(),
        codes: vec![1, 0, 1, 1, 0],
        levels_offsets: vec![0, 2, 5],
        levels_bytes: b"lohi!".to_vec(),
    }
}

fn addr<T>(v: &[T]) -> usize {
    v.as_ptr() as usize
}

/// Three fields (Int64 with a null and metadata, Utf8, an ordered
/// dictionary of Utf8) in two batches, the second a window at offset 2.
fn table(b: &Buffers, owner: &Owner) -> Table {
    let mut n = Field::new("n", "l");
    n.metadata = Some(metadata(&[("k", b"v"), ("empty", b"")]));
    let s = Field::new("s", "u");
    let mut c = Field::new("c", "c");
    c.flags |= DICTIONARY_ORDERED;
    c.dictionary = Some(Box::new(Field::new("", "u")));
    let child = |length, null_count, offset, buffers: Vec<usize>, dictionary: Option<Box<Array>>| Array {
        length,
        null_count,
        offset,
        buffers,
        children: Vec::new(),
        dictionary,
        owner: None,
    };
    let levels = Box::new(child(2, 0, 0, vec![0, addr(&b.levels_offsets), addr(&b.levels_bytes)], None));
    let batch = |length: usize, offset: usize, nulls: usize| Array {
        length,
        null_count: 0,
        offset: 0,
        buffers: vec![0],
        children: vec![
            child(length, nulls, offset, vec![addr(&b.ints_valid), addr(&b.ints)], None),
            child(length, 0, offset, vec![0, addr(&b.offsets), addr(&b.bytes)], None),
            child(length, 0, offset, vec![0, addr(&b.codes)], Some(levels.clone())),
        ],
        dictionary: None,
        owner: Some(owner.clone()),
    };
    Table { fields: vec![n, s, c], batches: vec![batch(5, 0, 1), batch(3, 2, 0)] }
}

fn same_field(want: &Field, got: &InField) {
    assert_eq!(got.name, want.name);
    assert_eq!(got.format, want.format);
    let want_meta = want.metadata.as_deref().map(parse_metadata).unwrap_or_default();
    assert_eq!(got.metadata, want_meta, "{}", want.name);
    assert_eq!(got.children.len(), want.children.len());
    for (w, g) in want.children.iter().zip(&got.children) {
        same_field(w, g);
    }
    match (&want.dictionary, &got.dictionary) {
        (None, None) => {}
        (Some(w), Some(g)) => same_field(w, g),
        _ => panic!("{}: a dictionary on one side only", want.name),
    }
}

/// The interface's metadata layout, decoded here independently of
/// `ffi::metadata`: an i32 count, then each key and value with an i32
/// length.
fn parse_metadata(bytes: &[u8]) -> Vec<(String, Vec<u8>)> {
    let int = |at: usize| i32::from_ne_bytes(bytes[at..at + 4].try_into().unwrap()) as usize;
    let mut at = 4;
    let mut out = Vec::new();
    for _ in 0..int(0) {
        let k = int(at);
        let key = String::from_utf8(bytes[at + 4..at + 4 + k].to_vec()).unwrap();
        at += 4 + k;
        let v = int(at);
        out.push((key, bytes[at + 4..at + 4 + v].to_vec()));
        at += 4 + v;
    }
    out
}

fn same_array(want: &Array, got: ArrayRef<'_>) {
    assert_eq!(got.len(), want.length);
    assert_eq!(got.offset(), want.offset);
    assert_eq!(got.null_count(), want.null_count as i64);
    assert_eq!(got.n_buffers(), want.buffers.len());
    for (i, &b) in want.buffers.iter().enumerate() {
        assert_eq!(got.buffer(i), b, "buffer {i}");
    }
    for (i, w) in want.children.iter().enumerate() {
        same_array(w, got.child(i).expect("a child"));
    }
    assert!(got.child(want.children.len()).is_none());
    match (&want.dictionary, got.dictionary()) {
        (None, None) => {}
        (Some(w), Some(g)) => same_array(w, g),
        _ => panic!("a dictionary on one side only"),
    }
}

#[test]
fn a_table_exported_and_imported_again_gives_the_same_buffers() {
    let b = Arc::new(buffers());
    let owner: Owner = b.clone();
    let t = table(&b, &owner);
    let mut stream = export_stream(&t);
    // SAFETY: a stream just exported, read by no one else.
    let imported = unsafe { import_stream(&mut stream) }.unwrap();
    assert!(stream.release.is_none(), "the stream moved out");

    assert_eq!(imported.schema.format, "+s");
    assert_eq!(imported.schema.children.len(), t.fields.len());
    for (w, g) in t.fields.iter().zip(&imported.schema.children) {
        same_field(w, g);
    }
    assert_eq!(imported.schema.children[0].meta("k"), Some(&b"v"[..]));
    assert_eq!(imported.batches.len(), t.batches.len());
    for (w, g) in t.batches.iter().zip(&imported.batches) {
        same_array(w, g.get());
    }

    // The values, read through the imported views.
    let first = imported.batches[0].get();
    let ints = first.child(0).unwrap();
    assert_eq!((0..5).map(|i| valid(&ints, i)).collect::<Vec<_>>(), [true, false, true, true, true]);
    let past_the_end = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| valid(&ints, 5)));
    assert!(past_the_end.is_err(), "valid() checks the row against the array's length");
    let text = first.child(1).unwrap();
    // SAFETY: a Utf8 array with five rows.
    let rows: Vec<&[u8]> = (0..5).map(|i| unsafe { text_at(&text, "u", i) }).collect();
    assert_eq!(rows, [&b"abc"[..], b"", b"defgh", b"i", b"jklm"]);
    let window = imported.batches[1].get().child(1).unwrap();
    // SAFETY: as above; the window starts at row 2.
    let rows: Vec<&[u8]> = (2..5).map(|i| unsafe { text_at(&window, "u", i) }).collect();
    assert_eq!(rows, [&b"defgh"[..], b"i", b"jklm"]);

    // The stream's copy of the table and every imported batch hold the
    // owner until the batches are dropped.
    assert!(Arc::strong_count(&b) > 2);
    drop(imported);
    drop(t);
    drop(owner);
    assert_eq!(Arc::strong_count(&b), 1, "every exported array was released");
}

/// A stream owned by the test: it hands on the batches of an exported
/// stream, counts its releases, and can fail where told.
struct Counted {
    inner: ArrowArrayStream,
    releases: Arc<AtomicUsize>,
    fail_schema: bool,
    fail_after: Option<usize>,
    given: usize,
}

unsafe fn counted<'a>(s: *mut ArrowArrayStream) -> &'a mut Counted {
    &mut *((*s).private_data as *mut Counted)
}

unsafe extern "C" fn get_schema(s: *mut ArrowArrayStream, out: *mut ArrowSchema) -> c_int {
    let p = counted(s);
    if p.fail_schema {
        return 5;
    }
    (p.inner.get_schema.unwrap())(&mut p.inner, out)
}

unsafe extern "C" fn get_next(s: *mut ArrowArrayStream, out: *mut ArrowArray) -> c_int {
    let p = counted(s);
    if p.fail_after == Some(p.given) {
        return 5;
    }
    p.given += 1;
    (p.inner.get_next.unwrap())(&mut p.inner, out)
}

unsafe extern "C" fn get_last_error(_: *mut ArrowArrayStream) -> *const c_char {
    c"the test said so".as_ptr()
}

unsafe extern "C" fn release(s: *mut ArrowArrayStream) {
    let mut p = Box::from_raw((*s).private_data as *mut Counted);
    p.releases.fetch_add(1, Ordering::SeqCst);
    if let Some(r) = p.inner.release {
        r(&mut p.inner);
    }
    (*s).release = None;
}

/// Import a counted stream of the test table; how many times it was
/// released, how many owners of its buffers are left, and the import's
/// error.
fn import_counted(fail_schema: bool, fail_after: Option<usize>) -> (usize, usize, Option<String>) {
    let b = Arc::new(buffers());
    let owner: Owner = b.clone();
    let t = table(&b, &owner);
    drop(owner);
    let releases = Arc::new(AtomicUsize::new(0));
    let private = Box::new(Counted { inner: export_stream(&t), releases: releases.clone(), fail_schema, fail_after, given: 0 });
    drop(t);
    let mut stream = ArrowArrayStream {
        get_schema: Some(get_schema),
        get_next: Some(get_next),
        get_last_error: Some(get_last_error),
        release: Some(release),
        private_data: Box::into_raw(private) as *mut c_void,
    };
    // SAFETY: a valid stream that no one else reads.
    let result = unsafe { import_stream(&mut stream) };
    assert!(stream.release.is_none(), "the stream moved out");
    let error = match result {
        Ok(imported) => {
            assert_eq!(releases.load(Ordering::SeqCst), 1, "released when the import ends");
            assert_eq!(imported.batches.len(), 2);
            drop(imported);
            None
        }
        Err(e) => Some(e.to_string()),
    };
    (releases.load(Ordering::SeqCst), Arc::strong_count(&b) - 1, error)
}

#[test]
fn a_stream_imported_and_released_frees_once() {
    assert_eq!(import_counted(false, None), (1, 0, None));
}

#[test]
fn a_stream_that_fails_is_released_once() {
    let schema = "reading the Arrow stream (schema): the test said so".to_string();
    let batch = "reading the Arrow stream (a batch): the test said so".to_string();
    assert_eq!(import_counted(true, None), (1, 0, Some(schema)));
    // Before any batch, and after one: the batch taken is freed too.
    assert_eq!(import_counted(false, Some(0)), (1, 0, Some(batch.clone())));
    assert_eq!(import_counted(false, Some(1)), (1, 0, Some(batch)));
}
