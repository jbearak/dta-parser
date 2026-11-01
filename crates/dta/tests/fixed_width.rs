//! Fixed-width text read through SAS setup files (plan 0009). The setups
//! and data are written here; what they should give follows from the
//! setup text and SAS's rules for column input, record selection and
//! missing values, written into each test.

use dta::{fixed_width_to_dta, Bytes, Column, Options, Reader, Recodes, StorageType, ValueLabelSet, WarningKind};

struct Got {
    names: Vec<String>,
    storage: Vec<StorageType>,
    labels: Vec<String>,
    set_of: Vec<String>,
    columns: Vec<Column>,
    sets: Vec<ValueLabelSet>,
    warnings: Vec<(WarningKind, String)>,
}

impl Got {
    fn k(&self, name: &str) -> usize {
        self.names.iter().position(|n| n == name).unwrap_or_else(|| panic!("no {name} in {:?}", self.names))
    }

    /// Values of a numeric variable: `Ok(number)` or `Err(missing code)`.
    fn nums(&self, name: &str) -> Vec<Result<f64, u8>> {
        match &self.columns[self.k(name)] {
            Column::Numbers { values, missing } => {
                values.iter().zip(missing).map(|(&v, &m)| if m == 0 { Ok(v) } else { Err(m) }).collect()
            }
            _ => panic!("{name} is not numeric"),
        }
    }

    fn strs(&self, name: &str) -> Vec<String> {
        let c = &self.columns[self.k(name)];
        (0..c.len()).map(|i| String::from_utf8(c.bytes(i).to_vec()).unwrap()).collect()
    }

    fn storage(&self, name: &str) -> StorageType {
        self.storage[self.k(name)]
    }

    fn label(&self, name: &str) -> &str {
        &self.labels[self.k(name)]
    }

    /// The value labels of a variable: (value or missing code, text).
    fn value_labels(&self, name: &str) -> Vec<(String, String)> {
        let set = &self.set_of[self.k(name)];
        let set = self.sets.iter().find(|s| &s.name == set).unwrap_or_else(|| panic!("{name} has no set"));
        let mut out: Vec<(String, String)> = set
            .labels
            .iter()
            .map(|l| (if l.missing == 0 { format!("{}", l.value) } else { dta::missing::name(l.missing).unwrap() }, l.text.clone()))
            .collect();
        out.sort();
        out
    }

    fn kinds(&self) -> Vec<WarningKind> {
        self.warnings.iter().map(|w| w.0).collect()
    }
}

fn read(setup: &str, data: &str, recodes: Recodes) -> Got {
    try_read(setup, data.as_bytes(), recodes).unwrap()
}

fn try_read(setup: &str, data: &[u8], recodes: Recodes) -> dta::Result<Got> {
    let mut out = Vec::new();
    let warnings = fixed_width_to_dta(setup.as_bytes(), data, recodes, &mut out)?;
    let mut r = Reader::open(Bytes(out), Options::default()).unwrap();
    let meta = r.metadata().clone();
    let all: Vec<usize> = (0..meta.variables.len()).collect();
    let columns = r.read(&all, 0, meta.nobs).unwrap();
    Ok(Got {
        names: meta.variables.iter().map(|v| v.name.clone()).collect(),
        storage: meta.variables.iter().map(|v| v.storage).collect(),
        labels: meta.variables.iter().map(|v| v.label.clone()).collect(),
        set_of: meta.variables.iter().map(|v| v.value_labels.clone()).collect(),
        columns,
        sets: r.value_labels().unwrap(),
        warnings: warnings.into_iter().map(|w| (w.kind, w.message)).collect(),
    })
}

fn err(setup: &str, data: &str) -> String {
    match try_read(setup, data.as_bytes(), Recodes::Setup) {
        Ok(_) => panic!("expected an error"),
        Err(e) => e.message,
    }
}

const M: u8 = 1; // `.`
const A: u8 = 2; // `.a`
const B: u8 = 3; // `.b`

/// A setup in the style CDC publishes: header comment, libname, formats,
/// an unnamed DATA step, INPUT, LABEL, recodes, FORMAT, RUN.
const CDC: &str = "/*----------------------------------------\r
 | SAS SETUP FILE: a test; with \"quotes\" and 'apostrophes'\r
 |---------------------------------------*/\r
\r
* DEFINING THE PATH;\r
libname \"data-file-path\";\r
\r
PROC FORMAT;\r
  VALUE sexf     1='(1) Boy' 2='(2) Girl' ;\r
  VALUE kidsf    0='(0) None' 98='(98) DK' 99='(99) Not ascertained' ;\r
  VALUE notef    1='(1) It''s; fine' -1='(-1) Before' ;\r
*/\r
\r
* SAS DATA, INFILE, INPUT STATEMENTS;\r
DATA ;\r
INFILE \"c:\\temp\\x.dat\" LRECL=12;\r
INPUT\r
\tID 1-3\t\tSEX 4\r
  KIDS 5-6   /*blank 7-7*/ NOTE 8-9\r
  NAME $ 10-12 ;\r
\r
* SAS LABEL STATEMENT;\r
LABEL\r
   ID   = 'Case number'\r
   SEX  = \"R's sex\"\r
   KIDS 'Number of kids'\r
   ;\r
\r
IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;\r
\r
FORMAT SEX sexf. KIDS kidsf. NOTE notef. ;\r
RUN ;\r
";

const CDC_DATA: &str = "0011 2  1Ann\r\n002298 -1Bo \r\n003199  0   \r\n004 99      \r\n";

#[test]
fn reads_a_cdc_style_setup() {
    let g = read(CDC, CDC_DATA, Recodes::Setup);
    assert_eq!(g.names, ["ID", "SEX", "KIDS", "NOTE", "NAME"]);
    assert!(g.warnings.is_empty(), "{:?}", g.warnings);
    assert_eq!(g.nums("ID"), [Ok(1.0), Ok(2.0), Ok(3.0), Ok(4.0)]);
    assert_eq!(g.nums("SEX"), [Ok(1.0), Ok(2.0), Ok(1.0), Err(M)]);
    assert_eq!(g.nums("KIDS"), [Ok(2.0), Err(M), Err(M), Err(M)]);
    assert_eq!(g.nums("NOTE"), [Ok(1.0), Ok(-1.0), Ok(0.0), Err(M)]);
    assert_eq!(g.strs("NAME"), ["Ann", "Bo", "", ""]);
    assert_eq!(g.label("ID"), "Case number");
    assert_eq!(g.label("SEX"), "R's sex");
    assert_eq!(g.label("KIDS"), "Number of kids");
    assert_eq!(g.label("NOTE"), "");
    assert_eq!(g.value_labels("NOTE"), [("-1".into(), "(-1) Before".into()), ("1".into(), "(1) It's; fine".into())]);
    // The recoded codes lose their labels: no value is 98 or 99 now.
    assert_eq!(g.value_labels("KIDS"), [("0".into(), "(0) None".into())]);
    assert_eq!(g.storage("ID"), StorageType::Byte);
    assert_eq!(g.storage("NAME"), StorageType::Str(3));
}

#[test]
fn tagged_recodes_keep_the_codes_as_letters() {
    let g = read(CDC, CDC_DATA, Recodes::Tagged);
    assert_eq!(g.nums("KIDS"), [Ok(2.0), Err(A), Err(B), Err(B)]);
    assert_eq!(
        g.value_labels("KIDS"),
        [(".a".into(), "(98) DK".into()), (".b".into(), "(99) Not ascertained".into()), ("0".into(), "(0) None".into())]
    );
    assert_eq!(g.set_of[g.k("KIDS")], "kidsf");
}

#[test]
fn recodes_none_keeps_the_codes() {
    let g = read(CDC, CDC_DATA, Recodes::None);
    assert_eq!(g.nums("KIDS"), [Ok(2.0), Ok(98.0), Ok(99.0), Ok(99.0)]);
    assert_eq!(g.value_labels("KIDS").len(), 3);
}

#[test]
fn letters_follow_the_setup_and_skip_its_own() {
    let setup = "DATA; INPUT A 1-2 B 3-4;
        IF B = 97 THEN B = .A;
        IF (B = 99 OR B = 98) THEN B = .;
        IF A = 9 THEN A = .;
        PROC FORMAT; VALUE bf 97='Refused' 98='DK';
        DATA; FORMAT B bf.;";
    let data = "0997\n0999\n0998\n0101\n";
    let g = read(setup, data, Recodes::Tagged);
    // .a is the setup's; 99 is named first, so it takes .b, then 98 .c.
    assert_eq!(g.nums("B"), [Err(A), Err(B), Err(4), Ok(1.0)]);
    assert_eq!(
        g.value_labels("B"),
        [(".a".into(), "Refused".into()), (".b".into(), "99".into()), (".c".into(), "DK".into())]
    );
    // A recoded variable with no format gets a set named after it.
    assert_eq!(g.nums("A"), [Err(A), Err(A), Err(A), Ok(1.0)]);
    assert_eq!(g.set_of[g.k("A")], "A");
    assert_eq!(g.value_labels("A"), [(".a".into(), "9".into())]);

    let g = read(setup, data, Recodes::Setup);
    // Setup mode: .A as written, with its label; `.` for the rest.
    assert_eq!(g.nums("B"), [Err(A), Err(M), Err(M), Ok(1.0)]);
    assert_eq!(g.value_labels("B"), [(".a".into(), "Refused".into())]);
    assert_eq!(g.set_of[g.k("A")], "");
}

#[test]
fn letters_the_setup_assigns_otherwise_are_reserved_too() {
    // `.a` comes from a statement that is not a recode; 98 takes `.b`.
    let setup = "DATA; INPUT X 1-2 Y 3; IF X = 1 AND Y = 1 THEN X = .A; IF X = 98 THEN X = .;";
    let g = read(setup, "011\n98 \n", Recodes::Tagged);
    assert_eq!(g.nums("X"), [Err(A), Err(B)]);
}

#[test]
fn codes_sent_to_one_letter_share_it() {
    let setup = "PROC FORMAT; VALUE f 8='DK' 9='NA';
        DATA; INPUT X 1; IF X = 9 OR X = 8 THEN X = .D; FORMAT X f.;";
    let g = read(setup, "8\n9\n1\n", Recodes::Tagged);
    assert_eq!(g.nums("X"), [Err(5), Err(5), Ok(1.0)]);
    assert_eq!(g.value_labels("X"), [(".d".into(), "DK / NA".into())]);
}

#[test]
fn more_than_26_letters_is_an_error() {
    let codes: Vec<String> = (1..=27).map(|i| format!("X = {i}")).collect();
    let setup = format!("DATA; INPUT X 1-2; IF {} THEN X = .;", codes.join(" OR "));
    let e = try_read(&setup, b"01\n", Recodes::Tagged).err().unwrap();
    assert!(e.message.contains("X recodes more codes"), "{}", e.message);
    assert!(try_read(&setup, b"01\n", Recodes::Setup).is_ok());
}

#[test]
fn derived_sets_are_shared_and_named() {
    let setup = "PROC FORMAT; VALUE yn 1='Yes' 2='No' 8='DK' 9='NA';
        DATA; INPUT A 1 B 2 C 3 D 4;
        IF (B = 8 OR B = 9) THEN B = .;
        IF (C = 8 OR C = 9) THEN C = .;
        IF D = 9 THEN D = .;
        FORMAT A B C D yn.;";
    let g = read(setup, "1289\n", Recodes::Setup);
    assert_eq!(g.set_of, ["yn", "yn_2", "yn_2", "yn_3"]);
    assert_eq!(g.value_labels("A").len(), 4);
    assert_eq!(g.value_labels("B"), [("1".into(), "Yes".into()), ("2".into(), "No".into())]);
    assert_eq!(g.value_labels("D").len(), 3);
    assert_eq!(g.sets.len(), 3);
}

#[test]
fn a_set_named_like_a_variable_is_not_taken() {
    // X has no format but needs labels for its letter; a VALUE named x
    // exists (unused), so X's set takes the next free name.
    let setup = "PROC FORMAT; VALUE x 1='one'; DATA; INPUT X 1; IF X = 9 THEN X = .;";
    let g = read(setup, "9\n", Recodes::Tagged);
    assert_eq!(g.set_of, ["X_2"]);
}

#[test]
fn a_label_followed_by_a_key_with_no_space() {
    // CDC's 1973 setup: 24='(20) Subfecund'33='(30) Fecund'.
    let setup = "PROC FORMAT; VALUE f 24='(20) Subfecund'33='(30) Fecund'; DATA; INPUT X 1-2; FORMAT X f.;";
    let g = read(setup, "33\n", Recodes::Setup);
    assert_eq!(g.value_labels("X"), [("24".into(), "(20) Subfecund".into()), ("33".into(), "(30) Fecund".into())]);
}

#[test]
fn derived_set_names_skip_taken_names_and_fit_32_characters() {
    // yn_2 is a VALUE of its own, so B's derived set takes yn_3.
    let setup = "PROC FORMAT; VALUE yn 1='Yes' 9='NA'; VALUE yn_2 1='One';
        DATA; INPUT A 1 B 2 C 3; IF B = 9 THEN B = .; FORMAT A yn. B yn. C yn_2.;";
    let g = read(setup, "199\n", Recodes::Setup);
    assert_eq!(g.set_of, ["yn", "yn_3", "yn_2"]);
    // A 32-character format name is shortened to fit its suffix.
    let long = "f".repeat(32);
    let setup = format!("PROC FORMAT; VALUE {long} 1='Yes' 9='NA'; DATA; INPUT A 1 B 2; IF B = 9 THEN B = .; FORMAT A B {long}.;");
    let g = read(&setup, "19\n", Recodes::Setup);
    assert_eq!(g.set_of, [long.clone(), format!("{}_2", "f".repeat(30))]);
}

#[test]
fn record_type_selection() {
    let setup = "DATA; INFILE 'x' LRECL=5;
        INPUT rec_type 1 @;
        if rec_type<5 then delete;
        else input ID 2-3 V 4-5;";
    let data = "1aaaa\n50102\n60203\n 0304\n";
    let g = read(setup, data, Recodes::Setup);
    assert_eq!(g.names, ["rec_type", "ID", "V"]);
    assert_eq!(g.nums("ID"), [Ok(1.0), Ok(2.0)]);
    // A blank type is missing, below every number, so `<5` drops it.
    for (cond, kept) in [
        ("rec_type>4", 2),
        ("rec_type=5", 3),
        ("rec_type ne 5", 1),
        ("rec_type^=5", 1),
        ("rec_type<=5", 1),
        ("rec_type GE 6", 3),
        ("rec_type > 0", 1),
        ("rec_type = .", 3),
        ("(rec_type=1 or rec_type=6) and rec_type>0", 2),
    ] {
        let s = setup.replace("rec_type<5", cond);
        let g = try_read(&s, data.as_bytes(), Recodes::Setup).unwrap();
        assert_eq!(g.columns[0].len(), kept, "{cond}");
    }
    // AND binds tighter than OR.
    let s = setup.replace("rec_type<5", "rec_type=1 or rec_type=5 and rec_type=6");
    assert_eq!(try_read(&s, data.as_bytes(), Recodes::Setup).unwrap().columns[0].len(), 3);
}

#[test]
fn fixed_records_without_line_breaks() {
    let setup = "DATA; INFILE 'x' recfm=f lrecl=4; INPUT A 1-2 B 3-4;";
    let g = read(setup, "0102030405  ", Recodes::Setup);
    assert_eq!(g.nums("A"), [Ok(1.0), Ok(3.0), Ok(5.0)]);
    assert_eq!(g.nums("B"), [Ok(2.0), Ok(4.0), Err(M)]);
    let e = err(setup, "01020");
    assert!(e.contains("1 bytes are left over"), "{e}");
}

#[test]
fn lines_and_lrecl() {
    // LF and CRLF; a last line without a break; LRECL cuts longer lines;
    // short lines read blank, with a warning.
    let setup = "DATA; INFILE 'x' LRECL=4; INPUT A 1-2 B 3-4;";
    let g = read(setup, "0102xx\r\n03\n0506", Recodes::Setup);
    assert_eq!(g.nums("A"), [Ok(1.0), Ok(3.0), Ok(5.0)]);
    assert_eq!(g.nums("B"), [Ok(2.0), Err(M), Ok(6.0)]);
    assert_eq!(g.kinds(), [WarningKind::ShortRecords]);
    assert!(g.warnings[0].1.starts_with("1 records are shorter than column 4"));
    // An empty last line is not a record.
    assert_eq!(read(setup, "0102\n", Recodes::Setup).nums("A").len(), 1);
}

#[test]
fn fields_that_are_not_numbers() {
    let setup = "DATA; INPUT A 1-3;";
    let g = read(setup, " 1 \n.  \nx1 \n-2 \n1.5\n", Recodes::Setup);
    assert_eq!(g.nums("A"), [Ok(1.0), Err(M), Err(M), Ok(-2.0), Ok(1.5)]);
    assert_eq!(g.kinds(), [WarningKind::NotANumber]);
    assert!(g.warnings[0].1.contains("A: 1 values are not numbers"));
    assert!(g.warnings[0].1.contains("record 3 of the data file"));
    // Record numbers are the data file's, also when records are dropped.
    let g = read("DATA; INPUT T 1 @; IF T = 1 THEN DELETE; ELSE INPUT A 2;", "1x\n2y\n", Recodes::Setup);
    assert!(g.warnings[0].1.contains("record 2 of the data file"), "{:?}", g.warnings);
}

#[test]
fn storage_types() {
    let setup = "DATA; INPUT A 1-6;";
    for (values, storage) in [
        ("100\n-127\n", StorageType::Byte),
        ("101\n", StorageType::Int),
        ("32740\n", StorageType::Int),
        ("32741\n", StorageType::Long),
        ("-32768\n", StorageType::Long),
        ("1.5\n", StorageType::Double),
        ("\n", StorageType::Byte),
    ] {
        assert_eq!(read(setup, values, Recodes::Setup).storage("A"), storage, "{values}");
    }
    // The type follows the values after the recodes.
    let setup = "DATA; INPUT A 1-3; IF A = 999 THEN A = .;";
    assert_eq!(read(setup, "1\n999\n", Recodes::Setup).storage("A"), StorageType::Byte);
    assert_eq!(read(setup, "1\n999\n", Recodes::None).storage("A"), StorageType::Int);
}

#[test]
fn repeated_names_keep_the_first_position_and_the_last_columns() {
    let setup = "DATA; INPUT A 1 B 2 A 3 FILLER 4 FILLER 4 C 5; LABEL FILLER='Blank' A 'first' A='last';";
    let g = read(setup, "12345\n", Recodes::Setup);
    assert_eq!(g.names, ["A", "B", "FILLER", "C"]);
    assert_eq!(g.nums("A"), [Ok(3.0)]);
    assert_eq!(g.label("A"), "last");
    assert_eq!(g.kinds(), [WarningKind::DuplicateName, WarningKind::DuplicateName]);
    let e = err("DATA; INPUT A 1 A $ 2;", "12\n");
    assert!(e.contains("both as a string and as a number"), "{e}");
}

#[test]
fn overlapping_columns() {
    let g = read("DATA; INPUT rec 1 MAR 1 AB 1-2;", "73\n", Recodes::Setup);
    assert_eq!((g.nums("rec"), g.nums("MAR"), g.nums("AB")), (vec![Ok(7.0)], vec![Ok(7.0)], vec![Ok(73.0)]));
}

#[test]
fn the_1973_assignments() {
    // The pair CDC's 1973 setup ends its INPUT with: a fix for one
    // record's string field, then a number made from it.
    let setup = "DATA; INPUT int_id 1-4 temp_NLAMOUNT $ 5-8 ;
        if int_id=3882 then temp_NLAMOUNT='0000';
        H_FINC_NLAMOUNT=input(temp_NLAMOUNT, 4.);
        LABEL H_FINC_NLAMOUNT = 'Amount';";
    let g = read(setup, "3881  12\n3882OOO0\n3883    \n", Recodes::Setup);
    assert_eq!(g.names, ["int_id", "temp_NLAMOUNT", "H_FINC_NLAMOUNT"]);
    assert_eq!(g.strs("temp_NLAMOUNT"), ["12", "0000", ""]);
    assert_eq!(g.nums("H_FINC_NLAMOUNT"), [Ok(12.0), Ok(0.0), Err(M)]);
    assert_eq!(g.label("H_FINC_NLAMOUNT"), "Amount");
    assert!(g.warnings.is_empty(), "{:?}", g.warnings);
}

#[test]
fn unsupported_data_step_order() {
    let e = err("DATA; INPUT s $ 1-2 x 3; n = input(s, 2.); if x = 1 then s = '9';", "123\n");
    assert!(e.contains("unsupported data-step order: s is assigned after INPUT() reads it"), "{e}");
    let e = err("DATA; INPUT a 1 b 2; if a = 1 then b = 2; if b = 2 then a = 3;", "12\n");
    assert!(e.contains("the condition reads b"), "{e}");
}

#[test]
fn skipped_and_unknown() {
    let setup = "PROC FORMAT; VALUE f 1-5='low' 6='six' OTHER='rest'; VALUE $s 'a'='A';
        DATA; INPUT X 1; LENGTH y 8; z = x * 2; LABEL Q='q'; FORMAT X f. Q f.;
        IF W = 1 THEN X = .; RUN; PROC PRINT; RUN;";
    let g = read(setup, "6\n", Recodes::Setup);
    assert_eq!(g.value_labels("X"), [("6".into(), "six".into())]);
    use WarningKind::*;
    let mut kinds = g.kinds();
    kinds.sort_by_key(|k| format!("{k:?}"));
    assert_eq!(
        kinds,
        [SkippedStatement, SkippedStatement, SkippedStatement, SkippedStatement, SkippedValueLabel, SkippedValueLabel, SkippedValueLabel, UnknownName, UnknownName, UnknownName]
    );
}

#[test]
fn long_labels() {
    let long = "x".repeat(200);
    let g = read(&format!("DATA; INPUT A 1; LABEL A='{long}';"), "1\n", Recodes::Setup);
    assert_eq!(g.label("A"), long);
    let longer = "é".repeat(200);
    let g = read(&format!("DATA; INPUT A 1; LABEL A='{longer}';"), "1\n", Recodes::Setup);
    assert_eq!(g.label("A"), "é".repeat(160));
    assert_eq!(g.kinds(), [WarningKind::LabelCut]);
}

#[test]
fn no_records_and_errors() {
    let g = read("DATA; INPUT A 1 @; IF A > 0 THEN DELETE;", "1\n2\n", Recodes::Setup);
    assert_eq!(g.kinds(), [WarningKind::NoRecords]);
    assert!(err("PROC FORMAT;", "").contains("no INPUT"));
    assert!(err("DATA; INPUT A 1. ;", "1\n").contains("INPUT form not supported"));
    assert!(err("DATA; INPUT A 3-2;", "1\n").contains("not a range"));
    assert!(err("DATA; INPUT A 1; LABEL A 3;", "1\n").contains("not a quoted string"));
    assert!(err("DATA; INFILE 'x' RECFM=F;", "1\n").contains("RECFM=F needs LRECL"));
    assert!(err("DATA; INPUT A 1; LABEL A='x;", "1\n").contains("not closed"));
}

#[test]
fn windows_1252_text() {
    let setup = b"DATA; INPUT S $ 1-2; LABEL S='caf\xe9';";
    let mut out = Vec::new();
    fixed_width_to_dta(setup, b"\xe9a\n", Recodes::Setup, &mut out).unwrap();
    let mut r = Reader::open(Bytes(out), Options::default()).unwrap();
    assert_eq!(r.metadata().variables[0].label, "café");
    let c = r.read(&[0], 0, 1).unwrap();
    assert_eq!(c[0].bytes(0), "éa".as_bytes());
}

/// compat/fixed_width's synthetic setup and data read as asciiSetupReader
/// reads them (compat/expected/fixed_width.json, ADR 0005).
#[test]
fn matches_ascii_setup_reader() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../compat");
    let setup = std::fs::read_to_string(root.join("fixed_width/synthetic.sas")).unwrap();
    let data = std::fs::read(root.join("fixed_width/synthetic.dat")).unwrap();
    let expected: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(root.join("expected/fixed_width.json")).unwrap()).unwrap();
    let g = try_read(&setup, &data, Recodes::Setup).unwrap();
    assert!(g.warnings.is_empty(), "{:?}", g.warnings);
    let theirs = expected["variables"].as_array().unwrap();
    let mut names: Vec<&str> = theirs.iter().map(|v| v["name"].as_str().unwrap()).collect();
    let mut ours: Vec<&str> = g.names.iter().map(String::as_str).collect();
    names.sort();
    ours.sort();
    assert_eq!(ours, names);
    let alnum = |s: &str| s.chars().filter(char::is_ascii_alphanumeric).collect::<String>();
    for v in theirs {
        let name = v["name"].as_str().unwrap();
        // asciiSetupReader turns labels into column names, adding the
        // variable's name where two labels are the same.
        let (label, want) = (alnum(g.label(name)), alnum(v["label"].as_str().unwrap()));
        assert!(want == label || want == label.clone() + name, "{name}: {label} {want}");
        let values = v["values"].as_array().unwrap();
        assert_eq!(values.len(), expected["nobs"].as_u64().unwrap() as usize);
        if name == "INTVWR" {
            let got = g.strs(name);
            for (row, (x, y)) in got.iter().zip(values).enumerate() {
                assert_eq!(x.as_str(), y.as_str().unwrap_or(""), "{name} row {row}");
            }
            continue;
        }
        for (row, (x, y)) in g.nums(name).iter().zip(values).enumerate() {
            match (x, y.as_f64()) {
                (Ok(a), Some(b)) => assert!((a - b).abs() <= 1e-9 * b.abs().max(1.0), "{name} row {row}: {a} {b}"),
                (Err(1), None) => {}
                _ => panic!("{name} row {row}: ours {x:?}, asciiSetupReader {y}"),
            }
        }
        // Setup mode drops the labels of codes recoded to `.`.
        let recoded: Vec<f64> = v["recoded"].as_array().unwrap().iter().map(|c| c.as_f64().unwrap()).collect();
        let mut want: Vec<(String, String)> = v["labels"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|p| !recoded.contains(&p[0].as_f64().unwrap()))
            .map(|p| (format!("{}", p[0].as_f64().unwrap()), p[1].as_str().unwrap().to_string()))
            .collect();
        want.sort();
        let got = if g.set_of[g.k(name)].is_empty() { Vec::new() } else { g.value_labels(name) };
        assert_eq!(got, want, "{name}");
    }
}

/// recodes = "tagged" on the same files gives what
/// compat/fixed_width/expected_fixed_width.R makes with asciiSetupReader
/// and haven: the codes read without the recodes, each recoded code a
/// tagged NA in the order the setup lists the recodes, and its label on
/// that letter.
#[test]
fn tagged_matches_ascii_setup_reader_and_haven() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../compat");
    let setup = std::fs::read_to_string(root.join("fixed_width/synthetic.sas")).unwrap();
    let data = std::fs::read(root.join("fixed_width/synthetic.dat")).unwrap();
    let expected: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(root.join("expected/fixed_width.json")).unwrap()).unwrap();
    let g = try_read(&setup, &data, Recodes::Tagged).unwrap();
    for v in expected["variables"].as_array().unwrap() {
        let name = v["name"].as_str().unwrap();
        let Some(tagged) = v["tagged"].as_array() else { continue };
        for (row, (x, y)) in g.nums(name).iter().zip(tagged).enumerate() {
            let want = match (y.as_f64(), y["missing"].as_str()) {
                (Some(b), _) => Ok(b),
                (None, Some(m)) => Err(dta::missing::from_name(m).unwrap()),
                (None, None) => Err(1),
            };
            match (x, want) {
                (Ok(a), Ok(b)) => assert!((a - b).abs() <= 1e-9 * b.abs().max(1.0), "{name} row {row}: {a} {b}"),
                (x, want) => assert_eq!(*x, want, "{name} row {row}"),
            }
        }
        let mut want: Vec<(String, String)> = v["tagged_labels"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| {
                let key = match p[0].as_f64() {
                    Some(c) => format!("{c}"),
                    None => p[0].as_str().unwrap().to_string(),
                };
                (key, p[1].as_str().unwrap().to_string())
            })
            .collect();
        want.sort();
        let got = if g.set_of[g.k(name)].is_empty() { Vec::new() } else { g.value_labels(name) };
        assert_eq!(got, want, "{name}");
    }
}
