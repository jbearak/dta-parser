//! Time and peak memory of reading a strL column (plan 0008 M1):
//! `cargo run --release --example strls -- write <path> <rows>` writes
//! a file of `rows` distinct strLs; `... -- one <path> <bytes> text|binary`
//! a file of one strL that long; `... -- read <path>` reads either.
//! Unix only (peak RSS from getrusage).

#[cfg(unix)]
fn main() {
    use dta::{FileSource, Options, Reader, StorageType, Values, WriteVariable};
    let args: Vec<String> = std::env::args().collect();
    let path = &args[2];
    if args[1] == "one" {
        let len: usize = args[3].parse().unwrap();
        let binary = args[4] == "binary";
        let value: &'static [u8] = vec![b'a'; len].leak();
        let data = dta::Dataset {
            nobs: 1,
            label: String::new(),
            timestamp: String::new(),
            variables: vec![WriteVariable {
                name: "s".into(),
                storage: StorageType::StrL,
                format: String::new(),
                label: String::new(),
                value_labels: String::new(),
                values: Values::StrLs(Box::new(move |_| (value, binary))),
            }],
            value_labels: vec![],
            characteristics: vec![],
            sort_order: vec![],
        };
        dta::write(&data, std::io::BufWriter::new(std::fs::File::create(path).unwrap())).unwrap();
        return;
    }
    if args[1] == "write" {
        let rows: usize = args[3].parse().unwrap();
        let data = dta::Dataset {
            nobs: rows,
            label: String::new(),
            timestamp: String::new(),
            variables: vec![WriteVariable {
                name: "s".into(),
                storage: StorageType::StrL,
                format: String::new(),
                label: String::new(),
                value_labels: String::new(),
                values: Values::StrLs(Box::new(|i| (Box::leak(format!("value {i}").into_boxed_str()).as_bytes(), false))),
            }],
            value_labels: vec![],
            characteristics: vec![],
            sort_order: vec![],
        };
        dta::write(&data, std::io::BufWriter::new(std::fs::File::create(path).unwrap())).unwrap();
        return;
    }
    let t = std::time::Instant::now();
    let mut r = Reader::open(FileSource::open(path).unwrap(), Options::default()).unwrap();
    let nobs = r.metadata().nobs;
    let mut bytes = 0usize;
    r.read_chunks(&[0], 0, nobs, None, |_, c| {
        bytes += c[0].len();
        Ok(())
    })
    .unwrap();
    let mut u: libc::rusage = unsafe { std::mem::zeroed() };
    unsafe { libc::getrusage(libc::RUSAGE_SELF, &mut u) };
    // macOS reports bytes, Linux kilobytes.
    let rss = if cfg!(target_os = "macos") { u.ru_maxrss as f64 / 1048576.0 } else { u.ru_maxrss as f64 / 1024.0 };
    println!("{nobs} strLs read in {:.2} s, peak RSS {rss:.0} MiB ({bytes} rows)", t.elapsed().as_secs_f64());
}

#[cfg(not(unix))]
fn main() {}
