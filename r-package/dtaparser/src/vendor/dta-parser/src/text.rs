use encoding_rs::WINDOWS_1252;

pub(crate) fn decode_utf8(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

pub(crate) fn decode_windows_1252(bytes: &[u8]) -> String {
    WINDOWS_1252
        .decode_without_bom_handling(bytes)
        .0
        .into_owned()
}

pub(crate) fn is_utf8_continuation(byte: u8) -> bool {
    byte & 0xc0 == 0x80
}

pub(crate) fn field_bytes(field: &[u8]) -> &[u8] {
    let end = field
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(field.len());
    &field[..end]
}
