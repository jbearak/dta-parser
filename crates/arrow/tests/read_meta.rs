//! A `.dta` read gives the `ReadMeta` that dta_parser's binding turns
//! into the dict datakit's `Meta` is made from (plan 0025, stage 2b).
//!
//! The fixture, compat/fixtures/haven_118.dta, was written by haven
//! (compat/make_fixtures.R). Its labels, formats and value labels are
//! those haven reads back (compat/expected/haven_118.haven.json); the
//! storage types, eligibility, letters and timestamp are what
//! `dta_read_arrow` gives Python for it.

use std::borrow::Cow;

use dta_arrow::dta::dta_read;
use dta_arrow::meta::{ColumnMeta, LabelKey, ReadMeta, ReadOutput};
use dta_arrow::read::Stamps;

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../compat/fixtures/haven_118.dta");

fn text(s: &str) -> Cow<'static, str> {
    Cow::Owned(s.to_string())
}

fn column(
    name: &str,
    label: Option<&str>,
    format: &str,
    value_labels: Option<&str>,
    storage: &str,
    eligible: bool,
) -> ColumnMeta<'static> {
    ColumnMeta {
        name: text(name),
        label: label.map(text),
        format: Some(text(format)),
        value_labels: value_labels.map(text),
        ordered: None,
        storage: Some(text(storage)),
        flag: None,
        eligible,
    }
}

/// `.` is missing code 1 and `.a` to `.z` are 2 to 27.
fn letter(l: char) -> LabelKey {
    LabelKey::Missing(l as u8 - b'a' + 2)
}

fn expected() -> ReadMeta<'static> {
    ReadMeta {
        rows: 6,
        columns: vec![
            column("row", None, "%12.0g", None, "long", true),
            column("num", Some("A double with extended missing values"), "%10.0g", None, "double", true),
            column("answer", Some("Labelled codes, some missing"), "%10.0g", Some("answer"), "double", true),
            column("count", Some("An integer"), "%12.0g", Some("count"), "long", true),
            column("text", Some("Text"), "%-9s", None, "str10", false),
            column("day", None, "%td", None, "double", true),
            column("big", None, "%-9s", None, "strL", false),
        ],
        value_labels: vec![
            (
                text("answer"),
                vec![
                    (LabelKey::Int(1), text("Yes")),
                    (LabelKey::Int(2), text("No")),
                    (letter('d'), text("Don't know")),
                    (letter('g'), text("Not in universe")),
                ],
            ),
            (text("count"), vec![(LabelKey::Int(0), text("None")), (LabelKey::Int(1), text("One"))]),
        ],
        label: Some("haven fixture".into()),
        notes: vec![],
        characteristics: vec![],
        sort: vec![],
        timestamp: Some("28 Oct 2026 15:17".into()),
        warnings: vec![],
        letter_columns: vec!["num".into(), "answer".into()],
        steps: None,
        release: Some(118),
    }
}

/// The letter codes (0 for `.a`) of one column of the letters table, None
/// where a row has none.
fn letters_of(out: &ReadOutput<'_>, k: usize) -> Vec<Option<u8>> {
    let table = out.letters.as_ref().expect("a letters table");
    let column = &table.batches[0].children[k];
    let (bits, keys) = (column.buffers[0] as *const u8, column.buffers[1] as *const u8);
    (0..column.length)
        // SAFETY: the read's buffers, alive while `out` is.
        .map(|r| unsafe { ((*bits.add(r / 8) >> (r % 8)) & 1 == 1).then(|| *keys.add(r)) })
        .collect()
}

#[test]
fn a_dta_read_gives_the_meta_python_holds() {
    dta_read(FIXTURE, None, 0, None, None, Stamps::Error, &mut |out| {
        assert_eq!(out.meta, expected());
        let names: Vec<&str> = out.frame.fields.iter().map(|f| f.name.as_str()).collect();
        assert_eq!(names, ["row", "num", "answer", "count", "text", "day", "big"]);

        let letters = out.letters.as_ref().expect("a letters table");
        let names: Vec<&str> = letters.fields.iter().map(|f| f.name.as_str()).collect();
        assert_eq!(names, ["num", "answer"]);
        // num: .a in row 4 and .z in row 5; answer: .d in row 3 and .g in row 4.
        assert_eq!(letters_of(&out, 0), [None, None, None, Some(0), Some(25), None]);
        assert_eq!(letters_of(&out, 1), [None, None, Some(3), Some(6), None, None]);
    })
    .unwrap();
}

#[test]
fn a_window_of_a_dta_read_gives_its_rows_and_letters() {
    dta_read(FIXTURE, None, 4, Some(2), None, Stamps::Error, &mut |out| {
        assert_eq!(out.meta.rows, 2);
        // Only num holds a letter in rows 5 and 6.
        assert_eq!(out.meta.letter_columns, ["num"]);
        assert_eq!(letters_of(&out, 0), [Some(25), None]);
    })
    .unwrap();
}
