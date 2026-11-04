//! Fixed-width text data read through a SAS setup file, as CDC publishes
//! the National Survey of Family Growth from 1973 to 2017-2019, and
//! written as release 118 for the language bindings to read back.
//!
//! The setup file is parsed for what such files hold: `PROC FORMAT`
//! value labels, `INFILE`'s record length, column `INPUT`, record-type
//! selection (`IF v < n THEN DELETE; ELSE INPUT ...`), `LABEL`, `FORMAT`,
//! and two forms of data-step assignment (`IF cond THEN v = constant`
//! and `v = INPUT(s, w.)`). Other statements are skipped with a warning,
//! except numeric `LENGTH`, which is skipped without one (ADR 0030).
//! A setup may come as several files (2002), read in order as one, and
//! its `PROC FORMAT` and `FORMAT` may be commented out (2006 to 2019).
//! Plan 0009 and ADR 0018 give the rules and the reasons.

use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::io::Write;

use crate::encoding::Encoding;
use crate::error::{Error, Result};
use crate::missing::{self, NOT_MISSING, SYSTEM};
use crate::reader::{ValueLabel, ValueLabelSet};
use crate::types::StorageType;
use crate::writer::{write_with, Dataset, Values, WriteOptions, WriteVariable};

/// What to do with the setup's missing-value recodes: statements such as
/// `IF (X = 98 OR X = 99) THEN X = .;`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Recodes {
    /// Apply them as written: a code recoded to `.` is `.`, one recoded
    /// to `.A` is `.a`.
    #[default]
    Setup,
    /// Give each code recoded to `.` a letter of its own, per variable in
    /// the order the setup names them (`.a`, `.b`, ...), with the code's
    /// label on the letter.
    Tagged,
    /// Ignore them: the codes stay numbers.
    None,
}

impl Recodes {
    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "setup" => Some(Recodes::Setup),
            "tagged" => Some(Recodes::Tagged),
            "none" => Some(Recodes::None),
            _ => None,
        }
    }
}

/// What a [`FixedWidthWarning`] is about.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WarningKind {
    /// A statement the converter does not run.
    SkippedStatement,
    /// A value label Stata cannot hold (a range, `OTHER`, a string key).
    SkippedValueLabel,
    /// `LABEL`, `FORMAT` or `IF` names a variable no `INPUT` defines.
    UnknownName,
    /// `INPUT` reads a name twice; the last spec gives the values.
    DuplicateName,
    /// Fields that are not numbers, read as `.`.
    NotANumber,
    /// Records shorter than the last column `INPUT` reads.
    ShortRecords,
    /// No record was kept.
    NoRecords,
    /// A variable label longer than 320 bytes, cut.
    LabelCut,
}

/// Something the converter did that the caller should know about.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FixedWidthWarning {
    pub kind: WarningKind,
    pub message: String,
}

/// Read `data` as `setups` describe and write it as release 118 to `out`.
///
/// `setups` are the setup's files, read in order as one setup; a
/// statement may not run from one file into the next. With several,
/// errors and warnings name the file by its place in `setups`, from 1.
/// With `commented_formats`, a block comment that holds only a `PROC
/// FORMAT` step or a `FORMAT` statement is read as code: CDC comments
/// them out of its 2006 to 2019 setups so that SAS runs without the
/// format catalog.
pub fn fixed_width_to_dta(
    setups: &[&[u8]],
    data: &[u8],
    recodes: Recodes,
    commented_formats: bool,
    out: impl Write,
) -> Result<Vec<FixedWidthWarning>> {
    let mut warnings = Vec::new();
    if setups.is_empty() {
        return Err(Error::invalid("no setup file was given"));
    }
    let texts: Vec<Cow<str>> = setups.iter().map(|s| text(s)).collect();
    let layout = parse_setup(&texts, commented_formats, &mut warnings)?;
    let records = split_records(data, &layout)?;
    let utf8 = std::str::from_utf8(data).is_ok();
    let program = Program::new(&layout, recodes)?;
    let kept: Vec<Rec> = records.into_iter().filter(|r| program.keep(data, r)).collect();
    if kept.is_empty() {
        warn(&mut warnings, WarningKind::NoRecords, "no record of the data file was kept".into());
    }
    let last_col = layout.vars.iter().filter_map(|v| v.cols.map(|(_, e)| e)).max().unwrap_or(0);
    let last_col = layout.lrecl.map_or(last_col, |l| last_col.min(l));
    let short = kept.iter().filter(|r| r.end - r.start < last_col).count();
    if short > 0 {
        warn(
            &mut warnings,
            WarningKind::ShortRecords,
            format!("{short} records are shorter than column {last_col}; is this the data file the setup describes?"),
        );
    }

    // One pass, record by record, for the numeric types, the invalid
    // fields and the string values.
    let n = layout.vars.len();
    let mut stats = vec![Stats::default(); n];
    let mut strings: Vec<Option<Vec<String>>> =
        layout.vars.iter().map(|v| v.is_str.then(|| Vec::with_capacity(kept.len()))).collect();
    let mut bad: Vec<(usize, usize)> = vec![(0, 0); n];
    for rec in &kept {
        for (k, var) in layout.vars.iter().enumerate() {
            if var.is_str {
                let s = program.string(data, rec, k);
                strings[k].as_mut().unwrap().push(decode(s, utf8));
            } else {
                let (v, code, invalid) = program.number(data, rec, k);
                if invalid {
                    if bad[k].0 == 0 {
                        bad[k].1 = rec.number;
                    }
                    bad[k].0 += 1;
                }
                stats[k].add(v, code);
            }
        }
    }
    for (k, &(count, first)) in bad.iter().enumerate() {
        if count > 0 {
            warn(
                &mut warnings,
                WarningKind::NotANumber,
                format!("{}: {count} values are not numbers and read as `.` (the first in record {first} of the data file)", layout.vars[k].name),
            );
        }
    }

    let sets = program.value_label_sets(&layout)?;
    let mut variables = Vec::with_capacity(n);
    for (k, var) in layout.vars.iter().enumerate() {
        let mut label = var.label.clone();
        if label.len() > 320 {
            let mut cut = 320;
            while !label.is_char_boundary(cut) {
                cut -= 1;
            }
            label.truncate(cut);
            warn(&mut warnings, WarningKind::LabelCut, format!("the label of {} is cut to 320 bytes", var.name));
        }
        let values = match &strings[k] {
            Some(s) => Values::Strings(Box::new(move |row| s[row].as_bytes())),
            None => {
                let (program, kept) = (&program, &kept);
                Values::Numbers(Box::new(move |first, values, codes| {
                    for (i, (v, c)) in values.iter_mut().zip(codes.iter_mut()).enumerate() {
                        (*v, *c, _) = program.number(data, &kept[first + i], k);
                    }
                }))
            }
        };
        variables.push(WriteVariable {
            name: var.name.clone(),
            storage: if var.is_str { StorageType::Str(1) } else { stats[k].storage() },
            format: String::new(),
            label,
            value_labels: sets.names[k].clone(),
            values,
        });
    }
    let dataset = Dataset {
        nobs: kept.len(),
        label: String::new(),
        timestamp: String::new(),
        variables,
        value_labels: sets.sets,
        characteristics: Vec::new(),
        sort_order: Vec::new(),
    };
    let options = WriteOptions { long_variable_labels: true, ..WriteOptions::default() };
    write_with(&dataset, out, &options)?;
    Ok(warnings)
}

fn warn(warnings: &mut Vec<FixedWidthWarning>, kind: WarningKind, message: String) {
    warnings.push(FixedWidthWarning { kind, message });
}

/// A file's text: UTF-8 when it all is, windows-1252 otherwise.
fn text(bytes: &[u8]) -> Cow<'_, str> {
    match std::str::from_utf8(bytes) {
        Ok(s) => Cow::Borrowed(s),
        Err(_) => Cow::Owned(Encoding::Windows1252.decode(bytes)),
    }
}

/// A string field's text, given whether its whole file is UTF-8.
fn decode(bytes: &[u8], utf8: bool) -> String {
    if utf8 {
        String::from_utf8_lossy(bytes).into_owned()
    } else {
        Encoding::Windows1252.decode(bytes)
    }
}

// ---------------------------------------------------------------------
// Tokens and statements

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    /// A name or keyword.
    Word(String),
    /// A number as written, such as `98`, `4.` or `1.5`.
    Num(String),
    /// A quoted string, quotes removed.
    Str(String),
    /// `.` (1) or `.a` to `.z` (2 to 27).
    Missing(u8),
    /// Punctuation: `=`, `<=`, `(`, `$`, `@`, ...
    Sym(String),
}

impl Tok {
    fn is_word(&self, w: &str) -> bool {
        matches!(self, Tok::Word(s) if s.eq_ignore_ascii_case(w))
    }

    fn is_sym(&self, s: &str) -> bool {
        matches!(self, Tok::Sym(t) if t == s)
    }

    fn show(&self) -> String {
        match self {
            Tok::Word(s) | Tok::Num(s) | Tok::Sym(s) => s.clone(),
            Tok::Str(s) => format!("'{s}'"),
            Tok::Missing(c) => missing::name(*c).unwrap_or_default(),
        }
    }
}

/// A place in the setup: its file's place among several (from 1), and the
/// line (from 1).
#[derive(Debug, Clone, Copy)]
struct Loc {
    file: Option<usize>,
    line: usize,
}

impl fmt::Display for Loc {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.file {
            Some(file) => write!(f, "file {file} line {}", self.line),
            None => write!(f, "line {}", self.line),
        }
    }
}

/// Where a token is in its file's text: bytes `start..end`, on `line`.
#[derive(Debug, Clone, Copy)]
struct Span {
    start: usize,
    end: usize,
    line: usize,
}

struct Statement {
    /// Where the statement's first token is.
    loc: Loc,
    toks: Vec<Tok>,
    /// Each token's place, in step with `toks`.
    spans: Vec<Span>,
}

impl Statement {
    fn show(&self) -> String {
        let s: Vec<String> = self.toks.iter().map(Tok::show).collect();
        let mut s = s.join(" ");
        if s.chars().count() > 80 {
            s = s.chars().take(77).collect::<String>() + "...";
        }
        format!("{}: {s};", self.loc)
    }

    fn error(&self, what: &str) -> Error {
        Error::invalid(format!("setup {}: {what}", self.loc))
    }

    /// The text of the setup file the statement is in.
    fn src<'s>(&self, texts: &'s [Cow<str>]) -> &'s str {
        &texts[self.loc.file.map_or(0, |f| f - 1)]
    }
}

/// Split SAS source into statements of tokens: comments dropped, quoted
/// strings kept whole, statements ended by `;` outside quotes. `file` is
/// the file's place among several setup files. With `commented_formats`,
/// a block comment between statements that [`commented_format`] accepts
/// is read as code.
fn statements(src: &str, file: Option<usize>, commented_formats: bool) -> Result<Vec<Statement>> {
    let b = src.as_bytes();
    let mut out = Vec::new();
    let mut toks: Vec<Tok> = Vec::new();
    let mut spans: Vec<Span> = Vec::new();
    let mut start_line = 0;
    let mut line = 1;
    let mut i = 0;
    // Where the block comment being read as code ends.
    let mut close: Option<usize> = None;
    while i < b.len() {
        let c = b[i];
        if close == Some(i) {
            close = None;
            i += 2;
        } else if c == b'\n' {
            line += 1;
            i += 1;
        } else if c.is_ascii_whitespace() {
            i += 1;
        } else if c == b'/' && b.get(i + 1) == Some(&b'*') {
            let body = i + 2;
            let end = (body..b.len()).find(|&j| b[j] == b'*' && b.get(j + 1) == Some(&b'/')).unwrap_or(b.len());
            if commented_formats && toks.is_empty() && close.is_none() && end < b.len() && commented_format(&src[body..end]) {
                close = Some(end);
                i = body;
            } else {
                line += b[i..end].iter().filter(|&&c| c == b'\n').count();
                if close == Some(end) {
                    close = None;
                }
                i = end + 2;
            }
        } else if c == b'*' && toks.is_empty() {
            // A comment statement, up to the next `;`.
            while i < b.len() && b[i] != b';' {
                line += (b[i] == b'\n') as usize;
                i += 1;
            }
            i += 1;
        } else if c == b';' {
            if !toks.is_empty() {
                let loc = Loc { file, line: start_line };
                out.push(Statement { loc, toks: std::mem::take(&mut toks), spans: std::mem::take(&mut spans) });
            }
            i += 1;
        } else {
            if toks.is_empty() {
                start_line = line;
            }
            let (tok, next) = token(b, i, Loc { file, line })?;
            spans.push(Span { start: i, end: next, line });
            line += b[i..next].iter().filter(|&&c| c == b'\n').count();
            toks.push(tok);
            i = next;
        }
    }
    if !toks.is_empty() {
        out.push(Statement { loc: Loc { file, line: start_line }, toks, spans });
    }
    Ok(out)
}

/// Whether a block comment's text, ignoring whitespace, is a `PROC FORMAT`
/// step (`PROC FORMAT;`, `VALUE` statements, and an optional `RUN;` or
/// `QUIT;`) or one `FORMAT` statement. A comment that only mentions them
/// is not.
fn commented_format(body: &str) -> bool {
    if !body.trim_end().ends_with(';') {
        return false;
    }
    let Ok(stmts) = statements(body, None, false) else { return false };
    match stmts.as_slice() {
        [proc, rest @ ..] if proc.toks[0].is_word("PROC") && proc.toks.get(1).is_some_and(|t| t.is_word("FORMAT")) => {
            let values = match rest {
                [values @ .., last] if last.toks.len() == 1 && (last.toks[0].is_word("RUN") || last.toks[0].is_word("QUIT")) => values,
                _ => rest,
            };
            !values.is_empty() && values.iter().all(|s| s.toks[0].is_word("VALUE"))
        }
        [format] if format.toks[0].is_word("FORMAT") => {
            let mut pairs = Vec::new();
            parse_format(format, &mut pairs).is_ok() && !pairs.is_empty()
        }
        _ => false,
    }
}

/// The token starting at `b[i]` and the index after it.
fn token(b: &[u8], i: usize, loc: Loc) -> Result<(Tok, usize)> {
    let c = b[i];
    let word_char = |c: u8| c.is_ascii_alphanumeric() || c == b'_';
    if c == b'\'' || c == b'"' {
        let mut s = Vec::new();
        let mut j = i + 1;
        loop {
            match b.get(j) {
                None => return Err(Error::invalid(format!("setup {loc}: a quoted string is not closed"))),
                Some(&q) if q == c && b.get(j + 1) == Some(&c) => {
                    s.push(c);
                    j += 2;
                }
                Some(&q) if q == c => break,
                Some(&x) => {
                    s.push(x);
                    j += 1;
                }
            }
        }
        // The source is valid UTF-8 and quotes are ASCII, so this is too.
        return Ok((Tok::Str(String::from_utf8_lossy(&s).into_owned()), j + 1));
    }
    if c.is_ascii_alphabetic() || c == b'_' {
        let mut j = i;
        while j < b.len() && word_char(b[j]) {
            j += 1;
        }
        return Ok((Tok::Word(String::from_utf8_lossy(&b[i..j]).into_owned()), j));
    }
    if c.is_ascii_digit() || (c == b'.' && b.get(i + 1).is_some_and(u8::is_ascii_digit)) {
        let mut j = i;
        while j < b.len() && b[j].is_ascii_digit() {
            j += 1;
        }
        if b.get(j) == Some(&b'.') {
            j += 1;
            while j < b.len() && b[j].is_ascii_digit() {
                j += 1;
            }
        }
        if matches!(b.get(j), Some(b'e' | b'E')) && b.get(j + 1).is_some_and(|d| d.is_ascii_digit() || *d == b'-' || *d == b'+') {
            j += 2;
            while j < b.len() && b[j].is_ascii_digit() {
                j += 1;
            }
        }
        return Ok((Tok::Num(String::from_utf8_lossy(&b[i..j]).into_owned()), j));
    }
    if c == b'.' {
        // `.A` but not `.ABC`; `.` alone (also ending a format name).
        if let Some(&l) = b.get(i + 1) {
            if (l.is_ascii_alphabetic() || l == b'_') && !b.get(i + 2).is_some_and(|&x| word_char(x)) {
                let code = if l == b'_' { SYSTEM } else { l.to_ascii_lowercase() - b'a' + 2 };
                return Ok((Tok::Missing(code), i + 2));
            }
        }
        return Ok((Tok::Missing(SYSTEM), i + 1));
    }
    for op in ["<=", ">=", "^=", "~=", "=<", "=>"] {
        if b[i..].starts_with(op.as_bytes()) {
            return Ok((Tok::Sym(op.into()), i + 2));
        }
    }
    let len = std::str::from_utf8(&b[i..]).ok().and_then(|s| s.chars().next()).map_or(1, char::len_utf8);
    Ok((Tok::Sym(String::from_utf8_lossy(&b[i..i + len]).into_owned()), i + len))
}

// ---------------------------------------------------------------------
// The setup's layout

#[derive(Debug, Clone, PartialEq)]
enum Const {
    Num(f64),
    Missing(u8),
    Str(String),
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Op {
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
}

#[derive(Debug, Clone)]
enum Cond {
    Cmp { var: usize, op: Op, value: Const },
    And(Box<Cond>, Box<Cond>),
    Or(Box<Cond>, Box<Cond>),
}

impl Cond {
    fn vars(&self, out: &mut Vec<usize>) {
        match self {
            Cond::Cmp { var, .. } => out.push(*var),
            Cond::And(a, b) | Cond::Or(a, b) => {
                a.vars(out);
                b.vars(out);
            }
        }
    }

    /// The codes of `X = a OR X = b ...` on `target`, or `None`.
    fn recode_codes(&self, target: usize, out: &mut Vec<f64>) -> bool {
        match self {
            Cond::Cmp { var, op: Op::Eq, value: Const::Num(v) } if *var == target => {
                out.push(*v);
                true
            }
            Cond::Or(a, b) => a.recode_codes(target, out) && b.recode_codes(target, out),
            _ => false,
        }
    }
}

struct Var {
    name: String,
    is_str: bool,
    /// The columns of its last `INPUT` spec, from 1; `None` for a
    /// variable made by `INPUT(...)`.
    cols: Option<(usize, usize)>,
    /// For a variable made by `name = INPUT(src, w.)`: `src` and `w`.
    from: Option<(usize, usize)>,
    label: String,
    format: Option<String>,
}

/// `IF cond THEN target = value`, in setup order.
struct Assign {
    loc: Loc,
    target: usize,
    cond: Cond,
    value: Const,
}

#[derive(Default)]
struct Layout {
    vars: Vec<Var>,
    /// `VALUE` sets by lower-case name, with their name as written.
    formats: HashMap<String, (String, Vec<ValueLabel>)>,
    /// Every `VALUE` name, lower case, string formats included.
    format_names: HashSet<String>,
    lrecl: Option<usize>,
    fixed: bool,
    /// Conditions under which a record is dropped.
    deletes: Vec<Cond>,
    assigns: Vec<Assign>,
    /// Variables made by `INPUT(...)`, with the number of `assigns`
    /// before their statement.
    made: Vec<(usize, usize)>,
    /// Variable index by lower-case name.
    by_name: HashMap<String, usize>,
}

impl Layout {
    fn find(&self, name: &str) -> Option<usize> {
        self.by_name.get(&name.to_ascii_lowercase()).copied()
    }
}

fn parse_setup(texts: &[Cow<str>], commented_formats: bool, warnings: &mut Vec<FixedWidthWarning>) -> Result<Layout> {
    let several = texts.len() > 1;
    let mut stmts = Vec::new();
    for (k, src) in texts.iter().enumerate() {
        stmts.extend(statements(src, several.then_some(k + 1), commented_formats)?);
    }
    let mut layout = Layout::default();
    let mut in_format = false;
    let mut in_data = false;
    // In a PROC step other than PROC FORMAT, whose statements are skipped.
    let mut in_other_proc = false;
    // A DATA step came earlier. CDC's 2002 setups put FORMAT after the
    // RUN of a PROC FORMAT step that follows the DATA step, so LABEL and
    // FORMAT outside any step apply to the DATA step's variables.
    let mut saw_data = false;
    let mut saw_input = false;
    // The previous statement was `IF ... THEN DELETE`, so `ELSE` may follow.
    let mut after_delete = false;
    let mut labels: Vec<(Loc, String, String)> = Vec::new();
    let mut formats: Vec<(Loc, String, String)> = Vec::new();
    let mut duplicates: Vec<String> = Vec::new();
    for st in &stmts {
        let head = match &st.toks[0] {
            Tok::Word(w) => w.to_ascii_uppercase(),
            _ => String::new(),
        };
        let was_after_delete = std::mem::take(&mut after_delete);
        match head.as_str() {
            "LIBNAME" | "OPTIONS" | "TITLE" | "FILENAME" => continue,
            // A number's LENGTH sets only how many bytes SAS stores it in.
            // A string's (`LENGTH s $ 5`) can cut what INPUT reads, so it
            // is skipped with a warning below. `LENGTH = ...` assigns a
            // variable named LENGTH.
            "LENGTH" if !st.toks.get(1).is_some_and(|t| t.is_sym("=")) && !st.toks.iter().any(|t| t.is_sym("$")) => continue,
            "RUN" | "QUIT" => {
                in_format = false;
                in_other_proc = false;
                continue;
            }
            "PROC" => {
                in_format = st.toks.get(1).is_some_and(|t| t.is_word("FORMAT"));
                in_other_proc = !in_format;
                in_data = false;
                if !in_format {
                    warn(warnings, WarningKind::SkippedStatement, format!("skipped {}", st.show()));
                }
                continue;
            }
            "DATA" => {
                in_format = false;
                in_other_proc = false;
                in_data = true;
                saw_data = true;
                continue;
            }
            "VALUE" if in_format => {
                parse_value(st, &mut layout, warnings)?;
                continue;
            }
            _ => {}
        }
        let outside = saw_data && !in_format && !in_other_proc && matches!(head.as_str(), "LABEL" | "FORMAT");
        if !in_data && !outside {
            warn(warnings, WarningKind::SkippedStatement, format!("skipped {}", st.show()));
            continue;
        }
        match head.as_str() {
            "INFILE" => parse_infile(st, &mut layout)?,
            "INPUT" => {
                parse_input(st, &st.toks[1..], &mut layout, &mut duplicates)?;
                saw_input = true;
            }
            "ELSE" if was_after_delete && st.toks.get(1).is_some_and(|t| t.is_word("INPUT")) => {
                parse_input(st, &st.toks[2..], &mut layout, &mut duplicates)?;
            }
            "LABEL" => parse_label(st, st.src(texts), &layout, &mut labels)?,
            "FORMAT" => parse_format(st, &mut formats)?,
            "IF" if saw_input => match parse_if(st, &mut layout, warnings)? {
                IfKind::Delete => after_delete = true,
                IfKind::Assign | IfKind::Skipped => {}
            },
            _ if saw_input && st.toks.len() > 2 && matches!(st.toks[0], Tok::Word(_)) && st.toks[1].is_sym("=") => {
                parse_assign_input(st, &mut layout, warnings)?;
            }
            _ => warn(warnings, WarningKind::SkippedStatement, format!("skipped {}", st.show())),
        }
    }
    if layout.vars.is_empty() {
        return Err(Error::invalid("the setup file has no INPUT statement"));
    }
    for name in duplicates {
        warn(
            warnings,
            WarningKind::DuplicateName,
            format!("INPUT reads {name} more than once; it keeps its first position and the values of its last columns"),
        );
    }
    for (loc, name, text) in labels {
        match layout.find(&name) {
            Some(k) => layout.vars[k].label = text,
            None => warn(warnings, WarningKind::UnknownName, format!("{loc}: LABEL names {name}, which INPUT does not define")),
        }
    }
    for (loc, name, fmt) in formats {
        match layout.find(&name) {
            Some(k) => layout.vars[k].format = Some(fmt),
            None => warn(warnings, WarningKind::UnknownName, format!("{loc}: FORMAT names {name}, which INPUT does not define")),
        }
    }
    check_order(&layout)?;
    Ok(layout)
}

fn parse_value(st: &Statement, layout: &mut Layout, warnings: &mut Vec<FixedWidthWarning>) -> Result<()> {
    let t = &st.toks;
    let (is_str, name, mut i) = match (t.get(1), t.get(2)) {
        (Some(Tok::Sym(s)), Some(Tok::Word(n))) if s == "$" => (true, n.clone(), 3),
        (Some(Tok::Word(n)), _) => (false, n.clone(), 2),
        _ => return Err(st.error("VALUE needs a format name")),
    };
    layout.format_names.insert(name.to_ascii_lowercase());
    if is_str {
        warn(warnings, WarningKind::SkippedValueLabel, format!("{}: skipped character format ${name}: Stata labels only numbers", st.loc));
        return Ok(());
    }
    // Options in parentheses, such as (MULTILABEL).
    if t.get(i).is_some_and(|x| x.is_sym("(")) {
        while i < t.len() && !t[i].is_sym(")") {
            i += 1;
        }
        i += 1;
    }
    let mut labels: Vec<ValueLabel> = Vec::new();
    while i < t.len() {
        let eq = (i..t.len()).find(|&j| t[j].is_sym("=")).ok_or_else(|| st.error(&format!("VALUE {name}: a value has no label")))?;
        let key = &t[i..eq];
        let text = match t.get(eq + 1) {
            Some(Tok::Str(s)) => s.clone(),
            _ => return Err(st.error(&format!("VALUE {name}: a label is not a quoted string"))),
        };
        i = eq + 2;
        let entry = match key {
            [Tok::Num(n)] => integer_key(n, false),
            [Tok::Sym(m), Tok::Num(n)] if m == "-" => integer_key(n, true),
            [Tok::Missing(c)] if *c > SYSTEM => Some(ValueLabel { value: f64::NAN, missing: *c, text: text.clone() }),
            _ => None,
        };
        match entry {
            Some(mut e) => {
                e.text = text;
                let same = |l: &ValueLabel| l.missing == e.missing && (l.missing != 0 || l.value == e.value);
                labels.retain(|l| !same(l));
                labels.push(e);
            }
            None => {
                let shown: Vec<String> = key.iter().map(Tok::show).collect();
                warn(
                    warnings,
                    WarningKind::SkippedValueLabel,
                    format!("{}: VALUE {name}: skipped the label of {}: Stata labels only whole numbers and .a to .z", st.loc, shown.join("")),
                );
            }
        }
    }
    layout.formats.insert(name.to_ascii_lowercase(), (name, labels));
    Ok(())
}

fn integer_key(n: &str, negative: bool) -> Option<ValueLabel> {
    let v: f64 = n.parse().ok()?;
    let v = if negative { -v } else { v };
    (v.fract() == 0.0 && (-2_147_483_647.0..=2_147_483_620.0).contains(&v))
        .then(|| ValueLabel { value: v, missing: NOT_MISSING, text: String::new() })
}

fn parse_infile(st: &Statement, layout: &mut Layout) -> Result<()> {
    let t = &st.toks;
    for i in 1..t.len() {
        if t[i].is_word("LRECL") && t.get(i + 1).is_some_and(|x| x.is_sym("=")) {
            match t.get(i + 2) {
                Some(Tok::Num(n)) => {
                    layout.lrecl = Some(n.parse().map_err(|_| st.error("LRECL is not a whole number"))?);
                }
                _ => return Err(st.error("LRECL is not a whole number")),
            }
        }
        if t[i].is_word("RECFM") && t.get(i + 1).is_some_and(|x| x.is_sym("=")) {
            layout.fixed = t.get(i + 2).is_some_and(|x| x.is_word("F") || x.is_word("FB"));
        }
    }
    if layout.fixed && layout.lrecl.is_none_or(|l| l == 0) {
        return Err(st.error("RECFM=F needs LRECL"));
    }
    Ok(())
}

/// Column specs `name [$] start[-end]`, then an optional trailing `@`.
fn parse_input(st: &Statement, t: &[Tok], layout: &mut Layout, duplicates: &mut Vec<String>) -> Result<()> {
    let mut i = 0;
    let unsupported = |i: usize| {
        let rest: Vec<String> = t[i..].iter().take(4).map(Tok::show).collect();
        st.error(&format!(
            "INPUT form not supported at \"{}\": only column input (name [$] start-end) is read",
            rest.join(" ")
        ))
    };
    while i < t.len() {
        if t[i].is_sym("@") && i + 1 == t.len() {
            break;
        }
        let name = match &t[i] {
            Tok::Word(n) => n.clone(),
            _ => return Err(unsupported(i)),
        };
        i += 1;
        let is_str = t.get(i).is_some_and(|x| x.is_sym("$"));
        if is_str {
            i += 1;
        }
        let start = match t.get(i) {
            Some(Tok::Num(n)) => n.parse::<usize>().map_err(|_| unsupported(i))?,
            _ => return Err(unsupported(i - 1)),
        };
        i += 1;
        let mut end = start;
        if t.get(i).is_some_and(|x| x.is_sym("-")) {
            end = match t.get(i + 1) {
                Some(Tok::Num(n)) => n.parse::<usize>().map_err(|_| unsupported(i))?,
                _ => return Err(unsupported(i)),
            };
            i += 2;
        }
        if start == 0 || end < start {
            return Err(st.error(&format!("INPUT {name}: columns {start}-{end} are not a range")));
        }
        match layout.find(&name) {
            Some(k) => {
                let var = &mut layout.vars[k];
                if var.is_str != is_str {
                    return Err(st.error(&format!("INPUT reads {name} both as a string and as a number")));
                }
                var.cols = Some((start, end));
                if !duplicates.contains(&var.name) {
                    duplicates.push(var.name.clone());
                }
            }
            None => {
                layout.by_name.insert(name.to_ascii_lowercase(), layout.vars.len());
                layout.vars.push(Var { name, is_str, cols: Some((start, end)), from: None, label: String::new(), format: None });
            }
        }
    }
    Ok(())
}

/// `LABEL name [=] 'text' ...`. `src` is the text of the statement's file;
/// `layout` has the variables defined so far.
fn parse_label(st: &Statement, src: &str, layout: &Layout, out: &mut Vec<(Loc, String, String)>) -> Result<()> {
    let t = &st.toks;
    let mut i = 1;
    while i < t.len() {
        let name = match &t[i] {
            Tok::Word(n) => n.clone(),
            other => return Err(st.error(&format!("LABEL: expected a name, not {}", other.show()))),
        };
        i += 1;
        if t.get(i).is_some_and(|x| x.is_sym("=")) {
            i += 1;
        }
        match t.get(i) {
            Some(Tok::Str(s)) => match stray_quotes(st, i, layout) {
                Some(last) => {
                    // The text between the first quote and the last, with
                    // no warning: it can change only a variable label
                    // (ADR 0030).
                    let text = &src[st.spans[i].start + 1..st.spans[last].end - 1];
                    out.push((st.loc, name, text.to_string()));
                    i = last;
                }
                None => out.push((st.loc, name, s.clone())),
            },
            _ => return Err(st.error(&format!("LABEL {name}: the label is not a quoted string"))),
        }
        i += 1;
    }
    Ok(())
}

/// For a label whose text has stray quotes, such as CDC's 2011-2013
/// `SALMX1 = "FLAG INDICATING WHETHER " SAME AS LAST MONTH" WAS ..."`,
/// the index of the string that ends it. The string at `i` is followed by
/// words and strings, the last a string, up to the next `name =`, the
/// statement's end or the end of the string's line. Words and strings
/// that are all `name 'text'` pairs naming variables already defined are
/// labels without `=` instead (CDC's 1995 `STRTL069 'AG8 ...'`).
fn stray_quotes(st: &Statement, i: usize, layout: &Layout) -> Option<usize> {
    let t = &st.toks;
    let line = st.spans[i].line;
    let mut j = i + 1;
    while j < t.len() && st.spans[j].line == line && !(matches!(t[j], Tok::Word(_)) && t.get(j + 1).is_some_and(|x| x.is_sym("="))) {
        if !matches!(t[j], Tok::Word(_) | Tok::Str(_)) {
            return None;
        }
        j += 1;
    }
    let rest = &t[i + 1..j];
    if !matches!(rest.last(), Some(Tok::Str(_))) {
        return None;
    }
    let labels = rest.len() % 2 == 0
        && rest.chunks(2).all(|p| matches!(&p[0], Tok::Word(n) if layout.find(n).is_some()) && matches!(p[1], Tok::Str(_)));
    (!labels).then_some(j - 1)
}

/// `FORMAT names fmt. names fmt. ...`. Formats are kept by lower-case
/// name; ones no `VALUE` defines are ignored later.
fn parse_format(st: &Statement, out: &mut Vec<(Loc, String, String)>) -> Result<()> {
    let t = &st.toks;
    let mut names: Vec<String> = Vec::new();
    let mut i = 1;
    while i < t.len() {
        match (&t[i], t.get(i + 1)) {
            (Tok::Word(f), Some(Tok::Missing(SYSTEM))) => {
                for n in names.drain(..) {
                    out.push((st.loc, n, f.to_ascii_lowercase()));
                }
                i += 2;
            }
            (Tok::Sym(s), Some(Tok::Word(_))) if s == "$" => {
                // A character format: no labels.
                names.clear();
                i += 3;
            }
            (Tok::Num(_), _) => {
                // A SAS format such as 8.2 or 5.
                names.clear();
                i += 1 + t.get(i + 1).is_some_and(|x| matches!(x, Tok::Missing(SYSTEM))) as usize;
            }
            (Tok::Word(n), _) => {
                names.push(n.clone());
                i += 1;
            }
            (other, _) => return Err(st.error(&format!("FORMAT: unexpected {}", other.show()))),
        }
    }
    Ok(())
}

enum IfKind {
    Delete,
    Assign,
    Skipped,
}

/// `IF cond THEN DELETE` or `IF cond THEN name = constant`.
fn parse_if(st: &Statement, layout: &mut Layout, warnings: &mut Vec<FixedWidthWarning>) -> Result<IfKind> {
    let t = &st.toks;
    let skip = |warnings: &mut Vec<FixedWidthWarning>| {
        warn(warnings, WarningKind::SkippedStatement, format!("skipped {}", st.show()));
        Ok(IfKind::Skipped)
    };
    let Some(then) = t.iter().position(|x| x.is_word("THEN")) else {
        return skip(warnings);
    };
    let mut p = CondParser { t: &t[1..then], i: 0, layout, unknown: None };
    let cond = match p.or() {
        Ok(c) if p.i == p.t.len() => c,
        _ => {
            if let Some(name) = p.unknown {
                warn(warnings, WarningKind::UnknownName, format!("{}: IF names {name}, which INPUT does not define", st.loc));
            }
            return skip(warnings);
        }
    };
    let action = &t[then + 1..];
    if action.len() == 1 && action[0].is_word("DELETE") {
        layout.deletes.push(cond);
        return Ok(IfKind::Delete);
    }
    let (name, value) = match action {
        [Tok::Word(n), eq, v] if eq.is_sym("=") => (n, constant(std::slice::from_ref(v))),
        [Tok::Word(n), eq, m, v] if eq.is_sym("=") => (n, constant(&[m.clone(), v.clone()])),
        _ => return skip(warnings),
    };
    let Some(value) = value else { return skip(warnings) };
    let Some(target) = layout.find(name) else {
        warn(warnings, WarningKind::UnknownName, format!("{}: IF assigns {name}, which INPUT does not define", st.loc));
        return skip(warnings);
    };
    let var = &layout.vars[target];
    match (&value, var.is_str) {
        (Const::Str(_), false) => return Err(st.error(&format!("IF assigns text to the number {}", var.name))),
        (Const::Num(_), true) => return Err(st.error(&format!("IF assigns a number to the string {}", var.name))),
        _ => {}
    }
    layout.assigns.push(Assign { loc: st.loc, target, cond, value });
    Ok(IfKind::Assign)
}

fn constant(t: &[Tok]) -> Option<Const> {
    match t {
        [Tok::Num(n)] => n.parse().ok().map(Const::Num),
        [Tok::Sym(m), Tok::Num(n)] if m == "-" => n.parse::<f64>().ok().map(|v| Const::Num(-v)),
        [Tok::Sym(m), Tok::Num(n)] if m == "+" => n.parse().ok().map(Const::Num),
        [Tok::Missing(c)] => Some(Const::Missing(*c)),
        [Tok::Str(s)] => Some(Const::Str(s.clone())),
        _ => None,
    }
}

struct CondParser<'a> {
    t: &'a [Tok],
    i: usize,
    layout: &'a Layout,
    unknown: Option<String>,
}

impl CondParser<'_> {
    fn or(&mut self) -> std::result::Result<Cond, ()> {
        let mut c = self.and()?;
        while self.t.get(self.i).is_some_and(|x| x.is_word("OR") || x.is_sym("|")) {
            self.i += 1;
            c = Cond::Or(Box::new(c), Box::new(self.and()?));
        }
        Ok(c)
    }

    fn and(&mut self) -> std::result::Result<Cond, ()> {
        let mut c = self.atom()?;
        while self.t.get(self.i).is_some_and(|x| x.is_word("AND") || x.is_sym("&")) {
            self.i += 1;
            c = Cond::And(Box::new(c), Box::new(self.atom()?));
        }
        Ok(c)
    }

    fn atom(&mut self) -> std::result::Result<Cond, ()> {
        if self.t.get(self.i).is_some_and(|x| x.is_sym("(")) {
            self.i += 1;
            let c = self.or()?;
            if !self.t.get(self.i).is_some_and(|x| x.is_sym(")")) {
                return Err(());
            }
            self.i += 1;
            return Ok(c);
        }
        let Some(Tok::Word(name)) = self.t.get(self.i) else { return Err(()) };
        let Some(var) = self.layout.find(name) else {
            self.unknown = Some(name.clone());
            return Err(());
        };
        let op = match self.t.get(self.i + 1) {
            Some(Tok::Sym(s)) => match s.as_str() {
                "=" => Op::Eq,
                "^=" | "~=" => Op::Ne,
                "<" => Op::Lt,
                "<=" | "=<" => Op::Le,
                ">" => Op::Gt,
                ">=" | "=>" => Op::Ge,
                _ => return Err(()),
            },
            Some(Tok::Word(w)) => match w.to_ascii_uppercase().as_str() {
                "EQ" => Op::Eq,
                "NE" => Op::Ne,
                "LT" => Op::Lt,
                "LE" => Op::Le,
                "GT" => Op::Gt,
                "GE" => Op::Ge,
                _ => return Err(()),
            },
            _ => return Err(()),
        };
        self.i += 2;
        let len = if self.t.get(self.i).is_some_and(|x| x.is_sym("-") || x.is_sym("+")) { 2 } else { 1 };
        let value = self.t.get(self.i..self.i + len).and_then(constant).ok_or(())?;
        self.i += len;
        if matches!(value, Const::Str(_)) != self.layout.vars[var].is_str {
            return Err(());
        }
        Ok(Cond::Cmp { var, op, value })
    }
}

/// `name = INPUT(src, w.)`, which makes a new numeric variable.
fn parse_assign_input(st: &Statement, layout: &mut Layout, warnings: &mut Vec<FixedWidthWarning>) -> Result<()> {
    let t = &st.toks;
    let parsed = match t.as_slice() {
        [Tok::Word(name), eq, f, open, Tok::Word(src), comma, Tok::Num(w), close]
            if eq.is_sym("=") && f.is_word("INPUT") && open.is_sym("(") && comma.is_sym(",") && close.is_sym(")") =>
        {
            w.strip_suffix('.').and_then(|w| w.parse::<usize>().ok()).map(|width| (name, src, width))
        }
        _ => None,
    };
    let Some((name, src, width)) = parsed else {
        warn(warnings, WarningKind::SkippedStatement, format!("skipped {}", st.show()));
        return Ok(());
    };
    let Some(src) = layout.find(src) else {
        warn(warnings, WarningKind::UnknownName, format!("{}: INPUT() reads {src}, which INPUT does not define", st.loc));
        warn(warnings, WarningKind::SkippedStatement, format!("skipped {}", st.show()));
        return Ok(());
    };
    if !layout.vars[src].is_str {
        return Err(st.error("INPUT() of a number is not supported"));
    }
    if layout.find(name).is_some() {
        return Err(st.error(&format!("{name} = INPUT(...) assigns a variable that already exists")));
    }
    let made = layout.vars.len();
    layout.by_name.insert(name.to_ascii_lowercase(), made);
    layout.vars.push(Var { name: name.clone(), is_str: false, cols: None, from: Some((src, width)), label: String::new(), format: None });
    layout.made.push((made, layout.assigns.len()));
    Ok(())
}

/// The order rule of plan 0009: a condition names only `INPUT`
/// variables no earlier statement assigns (apart from the target), and
/// `INPUT(src)` comes after every statement assigning `src`.
fn check_order(layout: &Layout) -> Result<()> {
    let mut assigned: HashSet<usize> = HashSet::new();
    for a in &layout.assigns {
        let mut vars = Vec::new();
        a.cond.vars(&mut vars);
        for v in vars {
            let var = &layout.vars[v];
            if var.from.is_some() || (v != a.target && assigned.contains(&v)) {
                return Err(Error::invalid(format!(
                    "setup {}: unsupported data-step order: the condition reads {}, which an earlier statement makes or assigns",
                    a.loc, var.name
                )));
            }
        }
        assigned.insert(a.target);
    }
    for &(made, before) in &layout.made {
        let src = layout.vars[made].from.unwrap().0;
        if let Some(a) = layout.assigns[before..].iter().find(|a| a.target == src) {
            return Err(Error::invalid(format!(
                "setup {}: unsupported data-step order: {} is assigned after INPUT() reads it",
                a.loc, layout.vars[src].name
            )));
        }
    }
    for c in &layout.deletes {
        let mut vars = Vec::new();
        c.vars(&mut vars);
        if let Some(&v) = vars.iter().find(|v| assigned.contains(v) || layout.vars[**v].from.is_some()) {
            return Err(Error::invalid(format!(
                "setup: unsupported data-step order: a record selection reads {}, which a statement makes or assigns",
                layout.vars[v].name
            )));
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------
// Records

/// A record: a byte range of the data file.
struct Rec {
    start: usize,
    end: usize,
    /// Its number in the data file, from 1.
    number: usize,
}

fn split_records(data: &[u8], layout: &Layout) -> Result<Vec<Rec>> {
    let mut out = Vec::new();
    if layout.fixed {
        let l = layout.lrecl.unwrap_or(1);
        if data.len() % l != 0 {
            return Err(Error::invalid(format!(
                "the data file's {} bytes are not whole records of LRECL={l}: {} bytes are left over",
                data.len(),
                data.len() % l
            )));
        }
        out.extend((0..data.len() / l).map(|i| Rec { start: i * l, end: (i + 1) * l, number: i + 1 }));
        return Ok(out);
    }
    let mut start = 0;
    while start < data.len() {
        let nl = data[start..].iter().position(|&c| c == b'\n').map_or(data.len(), |p| start + p);
        let mut end = nl;
        if end > start && data[end - 1] == b'\r' {
            end -= 1;
        }
        if let Some(l) = layout.lrecl {
            end = end.min(start + l);
        }
        out.push(Rec { start, end, number: out.len() + 1 });
        start = nl + 1;
    }
    Ok(out)
}

/// A field's bytes, blanks trimmed; columns past the record are blank.
fn field<'d>(data: &'d [u8], rec: &Rec, (start, end): (usize, usize)) -> &'d [u8] {
    let a = (rec.start + start - 1).min(rec.end);
    let b = (rec.start + end).min(rec.end);
    data[a..b].trim_ascii()
}

/// A numeric field: value, missing code, and whether it was not a number.
fn parse_number(s: &[u8]) -> (f64, u8, bool) {
    if s.is_empty() || s == b"." {
        return (0.0, SYSTEM, false);
    }
    let ok = s.iter().all(|c| c.is_ascii_digit() || matches!(c, b'+' | b'-' | b'.' | b'e' | b'E'));
    match std::str::from_utf8(s).ok().filter(|_| ok).and_then(|s| s.parse::<f64>().ok()) {
        Some(v) if v.is_finite() => (v, NOT_MISSING, false),
        _ => (0.0, SYSTEM, true),
    }
}

// ---------------------------------------------------------------------
// Values

/// A value during evaluation.
#[derive(Clone, Copy)]
enum Val<'a> {
    Num(f64, u8),
    Str(&'a [u8]),
}

/// One statement assigning a variable, as the chosen `recodes` mode
/// runs it.
enum Step {
    /// `IF cond THEN v = value`.
    Set { cond: Cond, value: Const },
    /// A recode: the codes and the missing code each becomes.
    Recode(Vec<(f64, u8)>),
}

struct Program<'l> {
    layout: &'l Layout,
    /// Per variable, its steps in order.
    steps: Vec<Vec<Step>>,
}

impl<'l> Program<'l> {
    fn new(layout: &'l Layout, recodes: Recodes) -> Result<Self> {
        let n = layout.vars.len();
        let mut steps: Vec<Vec<Step>> = (0..n).map(|_| Vec::new()).collect();
        // Letters `Tagged` gives each variable, by code.
        let mut letters: Vec<Vec<(f64, u8)>> = vec![Vec::new(); n];
        if recodes == Recodes::Tagged {
            let mut written: Vec<HashSet<u8>> = vec![HashSet::new(); n];
            let mut order: Vec<Vec<f64>> = vec![Vec::new(); n];
            for a in &layout.assigns {
                let mut codes = Vec::new();
                if let Const::Missing(c) = a.value {
                    // Every letter the setup assigns the variable is
                    // reserved, by a recode or any other statement.
                    if c != SYSTEM {
                        written[a.target].insert(c);
                    } else if a.cond.recode_codes(a.target, &mut codes) {
                        for code in codes {
                            if !order[a.target].contains(&code) {
                                order[a.target].push(code);
                            }
                        }
                    }
                }
            }
            for k in 0..n {
                let mut free = (2..=missing::LAST).filter(|c| !written[k].contains(c));
                for &code in &order[k] {
                    let Some(letter) = free.next() else {
                        return Err(Error::invalid(format!(
                            "{} recodes more codes to `.` than there are letters .a to .z; use recodes = \"setup\"",
                            layout.vars[k].name
                        )));
                    };
                    letters[k].push((code, letter));
                }
            }
        }
        for a in &layout.assigns {
            let mut codes = Vec::new();
            let recode = match a.value {
                Const::Missing(c) if a.cond.recode_codes(a.target, &mut codes) => Some(c),
                _ => None,
            };
            let step = match (recode, recodes) {
                (Some(_), Recodes::None) => continue,
                (Some(c), Recodes::Tagged) if c == SYSTEM => Step::Recode(
                    codes.iter().map(|&x| (x, letters[a.target].iter().find(|l| l.0 == x).map_or(SYSTEM, |l| l.1))).collect(),
                ),
                (Some(c), _) => Step::Recode(codes.iter().map(|&x| (x, c)).collect()),
                (None, _) => Step::Set { cond: a.cond.clone(), value: a.value.clone() },
            };
            steps[a.target].push(step);
        }
        Ok(Program { layout, steps })
    }

    /// Whether a record is kept: no `IF ... THEN DELETE` holds for it.
    fn keep(&self, data: &[u8], rec: &Rec) -> bool {
        !self.layout.deletes.iter().any(|c| self.test(data, rec, c, None))
    }

    /// The raw value of variable `k`: its field, or its `INPUT(...)`;
    /// and whether that was not a number.
    fn base<'d>(&'d self, data: &'d [u8], rec: &Rec, k: usize) -> (Val<'d>, bool) {
        let var = &self.layout.vars[k];
        if let Some((src, width)) = var.from {
            let s = self.string(data, rec, src);
            let (v, c, bad) = parse_number(s[..s.len().min(width)].trim_ascii());
            return (Val::Num(v, c), bad);
        }
        let f = field(data, rec, var.cols.unwrap());
        if var.is_str {
            (Val::Str(f), false)
        } else {
            let (v, c, bad) = parse_number(f);
            (Val::Num(v, c), bad)
        }
    }

    /// String variable `k`'s value after its statements.
    fn string<'d>(&'d self, data: &'d [u8], rec: &Rec, k: usize) -> &'d [u8] {
        let var = &self.layout.vars[k];
        let mut v = field(data, rec, var.cols.unwrap());
        for step in &self.steps[k] {
            if let Step::Set { cond, value } = step {
                if self.test(data, rec, cond, Some((k, Val::Str(v)))) {
                    v = match value {
                        Const::Str(s) => s.as_bytes().trim_ascii(),
                        _ => b"",
                    };
                }
            }
        }
        v
    }

    /// Variable `k`'s number after its statements, and whether its field
    /// was not a number.
    fn number(&self, data: &[u8], rec: &Rec, k: usize) -> (f64, u8, bool) {
        let (base, bad) = self.base(data, rec, k);
        let Val::Num(mut v, mut c) = base else { return (0.0, SYSTEM, false) };
        for step in &self.steps[k] {
            match step {
                Step::Set { cond, value } => {
                    if self.test(data, rec, cond, Some((k, Val::Num(v, c)))) {
                        (v, c) = match value {
                            Const::Num(x) => (*x, NOT_MISSING),
                            Const::Missing(m) => (0.0, *m),
                            Const::Str(_) => (v, c),
                        };
                    }
                }
                Step::Recode(codes) => {
                    if c == NOT_MISSING {
                        if let Some(&(_, m)) = codes.iter().find(|&&(x, _)| x == v) {
                            (v, c) = (0.0, m);
                        }
                    }
                }
            }
        }
        (v, c, bad)
    }

    /// Whether `cond` holds; `current` is the target's value so far.
    fn test(&self, data: &[u8], rec: &Rec, cond: &Cond, current: Option<(usize, Val)>) -> bool {
        match cond {
            Cond::And(a, b) => self.test(data, rec, a, current) && self.test(data, rec, b, current),
            Cond::Or(a, b) => self.test(data, rec, a, current) || self.test(data, rec, b, current),
            Cond::Cmp { var, op, value } => {
                let v = match current {
                    Some((k, v)) if k == *var => v,
                    _ => self.base(data, rec, *var).0,
                };
                let ord = match (v, value) {
                    (Val::Str(s), Const::Str(t)) => s.cmp(t.trim_end().as_bytes()),
                    (Val::Num(x, c), Const::Num(y)) => order((x, c), (*y, NOT_MISSING)),
                    (Val::Num(x, c), Const::Missing(m)) => order((x, c), (0.0, *m)),
                    _ => return false,
                };
                use std::cmp::Ordering::*;
                match op {
                    Op::Eq => ord == Equal,
                    Op::Ne => ord != Equal,
                    Op::Lt => ord == Less,
                    Op::Le => ord != Greater,
                    Op::Gt => ord == Greater,
                    Op::Ge => ord != Less,
                }
            }
        }
    }

    /// The value-label sets and each variable's set name (plan 0009).
    fn value_label_sets(&self, layout: &Layout) -> Result<Sets> {
        let mut reserved: HashSet<String> = layout.format_names.clone();
        let mut by_content: HashMap<(String, Vec<LabelKey>), String> = HashMap::new();
        let mut taken: HashSet<String> = HashSet::new();
        let mut sets = Vec::new();
        let mut names = Vec::with_capacity(layout.vars.len());
        for (k, var) in layout.vars.iter().enumerate() {
            let original = var.format.as_ref().and_then(|f| layout.formats.get(f));
            if var.is_str {
                names.push(String::new());
                continue;
            }
            let recoded: Vec<(f64, u8)> = self.steps[k]
                .iter()
                .flat_map(|s| match s {
                    Step::Recode(codes) => codes.clone(),
                    Step::Set { .. } => Vec::new(),
                })
                .collect();
            let base = match original {
                Some((name, _)) => name.clone(),
                None => var.name.clone(),
            };
            let mut labels: Vec<ValueLabel> = original.map(|o| o.1.clone()).unwrap_or_default();
            if !recoded.is_empty() {
                let text_of = |x: f64| labels.iter().find(|l| l.missing == 0 && l.value == x).map(|l| l.text.clone());
                let mut moved: Vec<(u8, Vec<(f64, String)>)> = Vec::new();
                for &(x, m) in &recoded {
                    if m == SYSTEM {
                        continue;
                    }
                    let text = text_of(x).unwrap_or_else(|| number_text(x));
                    match moved.iter_mut().find(|e| e.0 == m) {
                        Some(e) => {
                            if !e.1.iter().any(|t| t.0 == x) {
                                e.1.push((x, text));
                            }
                        }
                        None => moved.push((m, vec![(x, text)])),
                    }
                }
                labels.retain(|l| l.missing != 0 || !recoded.iter().any(|r| r.0 == l.value));
                for (m, mut texts) in moved {
                    texts.sort_by(|a, b| a.0.total_cmp(&b.0));
                    let mut text: Vec<String> = labels.iter().filter(|l| l.missing == m).map(|l| l.text.clone()).collect();
                    text.extend(texts.into_iter().map(|t| t.1));
                    labels.retain(|l| l.missing != m);
                    labels.push(ValueLabel { value: f64::NAN, missing: m, text: text.join(" / ") });
                }
            }
            if labels.is_empty() {
                names.push(String::new());
                continue;
            }
            let content: Vec<LabelKey> = labels.iter().map(LabelKey::of).collect();
            let key = (base.to_ascii_lowercase(), content);
            if let Some(name) = by_content.get(&key) {
                names.push(name.clone());
                continue;
            }
            let name = if !taken.contains(&base.to_ascii_lowercase())
                && (original.is_some() || !reserved.contains(&base.to_ascii_lowercase()))
            {
                base.clone()
            } else {
                (2..)
                    .map(|i| {
                        let suffix = format!("_{i}");
                        let keep = base.chars().take(32 - suffix.len()).collect::<String>();
                        keep + &suffix
                    })
                    .find(|n| !taken.contains(&n.to_ascii_lowercase()) && !reserved.contains(&n.to_ascii_lowercase()))
                    .unwrap()
            };
            taken.insert(name.to_ascii_lowercase());
            reserved.insert(name.to_ascii_lowercase());
            by_content.insert(key, name.clone());
            sets.push(ValueLabelSet { name: name.clone(), labels });
            names.push(name);
        }
        Ok(Sets { sets, names })
    }
}

struct Sets {
    sets: Vec<ValueLabelSet>,
    names: Vec<String>,
}

/// A value label, comparable.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct LabelKey(u64, u8, String);

impl LabelKey {
    fn of(l: &ValueLabel) -> Self {
        LabelKey(if l.missing == 0 { l.value.to_bits() } else { 0 }, l.missing, l.text.clone())
    }
}

fn number_text(x: f64) -> String {
    if x.fract() == 0.0 {
        format!("{}", x as i64)
    } else {
        format!("{x}")
    }
}

/// SAS's order: every missing value is below every number, and `.` is
/// below `.a` to `.z`.
fn order(a: (f64, u8), b: (f64, u8)) -> std::cmp::Ordering {
    match (a.1, b.1) {
        (0, 0) => a.0.total_cmp(&b.0),
        (0, _) => std::cmp::Ordering::Greater,
        (_, 0) => std::cmp::Ordering::Less,
        (x, y) => x.cmp(&y),
    }
}

/// Per numeric variable: what the values need of a storage type.
#[derive(Debug, Clone, Copy)]
struct Stats {
    any: bool,
    integer: bool,
    min: f64,
    max: f64,
}

impl Default for Stats {
    fn default() -> Self {
        Stats { any: false, integer: true, min: 0.0, max: 0.0 }
    }
}

impl Stats {
    fn add(&mut self, v: f64, code: u8) {
        if code != NOT_MISSING {
            return;
        }
        if !self.any {
            (self.min, self.max) = (v, v);
            self.any = true;
        }
        self.integer &= v.fract() == 0.0;
        self.min = self.min.min(v);
        self.max = self.max.max(v);
    }

    fn storage(&self) -> StorageType {
        let within = |lo: f64, hi: f64| self.min >= lo && self.max <= hi;
        if !self.any {
            StorageType::Byte
        } else if !self.integer {
            StorageType::Double
        } else if within(-127.0, 100.0) {
            StorageType::Byte
        } else if within(-32_767.0, 32_740.0) {
            StorageType::Int
        } else if within(-2_147_483_647.0, 2_147_483_620.0) {
            StorageType::Long
        } else {
            StorageType::Double
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokens() {
        let s = statements("/* c */ * x; y ;\r\nVALUE a -1='it''s; ok' 2=\"b\";\nFORMAT v fmt. w 8.2;", None, false).unwrap();
        assert_eq!(s.len(), 3);
        assert_eq!(s[0].toks, vec![Tok::Word("y".into())]);
        assert_eq!(s[1].toks, vec![Tok::Word("VALUE".into()), Tok::Word("a".into()), Tok::Sym("-".into()), Tok::Num("1".into()), Tok::Sym("=".into()), Tok::Str("it's; ok".into()), Tok::Num("2".into()), Tok::Sym("=".into()), Tok::Str("b".into())]);
        assert_eq!(s[1].loc.line, 2);
        assert_eq!(s[2].toks[2], Tok::Word("fmt".into()));
        assert_eq!(s[2].toks[3], Tok::Missing(SYSTEM));
        assert_eq!(s[2].toks[5], Tok::Num("8.2".into()));
    }

    #[test]
    fn missing_tokens() {
        let s = statements("x = .A; y = .; z = .5;", None, false).unwrap();
        assert_eq!(s[0].toks[2], Tok::Missing(2));
        assert_eq!(s[1].toks[2], Tok::Missing(SYSTEM));
        assert_eq!(s[2].toks[2], Tok::Num(".5".into()));
    }

    #[test]
    fn numbers() {
        assert_eq!(parse_number(b""), (0.0, SYSTEM, false));
        assert_eq!(parse_number(b"."), (0.0, SYSTEM, false));
        assert_eq!(parse_number(b"-12"), (-12.0, NOT_MISSING, false));
        assert_eq!(parse_number(b"1.5e2"), (150.0, NOT_MISSING, false));
        assert_eq!(parse_number(b"OOO0"), (0.0, SYSTEM, true));
        assert_eq!(parse_number(b"inf"), (0.0, SYSTEM, true));
    }

    #[test]
    fn missing_order() {
        use std::cmp::Ordering::*;
        assert_eq!(order((0.0, SYSTEM), (-1e300, 0)), Less);
        assert_eq!(order((0.0, SYSTEM), (0.0, 2)), Less);
        assert_eq!(order((3.0, 0), (3.0, 0)), Equal);
    }
}
