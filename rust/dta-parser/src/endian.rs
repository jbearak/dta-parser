use crate::{ByteOrder, DtaError};

pub(crate) fn checked_add(
    left: usize,
    right: usize,
    context: &'static str,
) -> Result<usize, DtaError> {
    left.checked_add(right)
        .ok_or(DtaError::ArithmeticOverflow(context))
}

pub(crate) fn checked_mul(
    left: usize,
    right: usize,
    context: &'static str,
) -> Result<usize, DtaError> {
    left.checked_mul(right)
        .ok_or(DtaError::ArithmeticOverflow(context))
}

pub(crate) fn slice_at<'a>(
    bytes: &'a [u8],
    offset: usize,
    length: usize,
    context: &'static str,
) -> Result<&'a [u8], DtaError> {
    let end = checked_add(offset, length, context)?;
    bytes.get(offset..end).ok_or_else(|| DtaError::Truncated {
        context,
        offset,
        needed: length,
        available: bytes.len().saturating_sub(offset),
    })
}

pub(crate) fn read_u8(bytes: &[u8], offset: usize, context: &'static str) -> Result<u8, DtaError> {
    Ok(slice_at(bytes, offset, 1, context)?[0])
}

pub(crate) fn read_u16(
    bytes: &[u8],
    offset: usize,
    byte_order: ByteOrder,
    context: &'static str,
) -> Result<u16, DtaError> {
    let value: [u8; 2] = slice_at(bytes, offset, 2, context)?
        .try_into()
        .expect("slice length was checked");
    Ok(match byte_order {
        ByteOrder::Lsf => u16::from_le_bytes(value),
        ByteOrder::Msf => u16::from_be_bytes(value),
    })
}

pub(crate) fn read_u32(
    bytes: &[u8],
    offset: usize,
    byte_order: ByteOrder,
    context: &'static str,
) -> Result<u32, DtaError> {
    let value: [u8; 4] = slice_at(bytes, offset, 4, context)?
        .try_into()
        .expect("slice length was checked");
    Ok(match byte_order {
        ByteOrder::Lsf => u32::from_le_bytes(value),
        ByteOrder::Msf => u32::from_be_bytes(value),
    })
}

pub(crate) fn read_u64(
    bytes: &[u8],
    offset: usize,
    byte_order: ByteOrder,
    context: &'static str,
) -> Result<u64, DtaError> {
    let value: [u8; 8] = slice_at(bytes, offset, 8, context)?
        .try_into()
        .expect("slice length was checked");
    Ok(match byte_order {
        ByteOrder::Lsf => u64::from_le_bytes(value),
        ByteOrder::Msf => u64::from_be_bytes(value),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_both_byte_orders() {
        let bytes = [1, 2, 3, 4, 5, 6, 7, 8];
        assert_eq!(read_u16(&bytes, 0, ByteOrder::Msf, "test").unwrap(), 0x0102);
        assert_eq!(read_u16(&bytes, 0, ByteOrder::Lsf, "test").unwrap(), 0x0201);
        assert_eq!(
            read_u32(&bytes, 0, ByteOrder::Msf, "test").unwrap(),
            0x0102_0304
        );
        assert_eq!(
            read_u64(&bytes, 0, ByteOrder::Lsf, "test").unwrap(),
            0x0807_0605_0403_0201
        );
    }

    #[test]
    fn reports_truncation_and_arithmetic_overflow() {
        assert!(matches!(
            read_u64(&[0; 7], 0, ByteOrder::Lsf, "u64"),
            Err(DtaError::Truncated { context: "u64", .. })
        ));
        assert_eq!(
            checked_add(usize::MAX, 1, "offset"),
            Err(DtaError::ArithmeticOverflow("offset"))
        );
        assert_eq!(
            checked_mul(usize::MAX, 2, "length"),
            Err(DtaError::ArithmeticOverflow("length"))
        );
    }
}
