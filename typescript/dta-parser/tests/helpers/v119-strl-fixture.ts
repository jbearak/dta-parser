export type FixtureByteOrder = 'LSF' | 'MSF';

export const V119_STRL_VALUE = 'release 119 strL';

const ASCII_ENCODER = new TextEncoder();

function push_ascii(bytes: number[], value: string): void {
    bytes.push(...ASCII_ENCODER.encode(value));
}

function push_fixed(
    bytes: number[],
    value: string,
    width: number
): void {
    const my_value = ASCII_ENCODER.encode(value);
    if (my_value.length > width) {
        throw new Error('Synthetic fixture field exceeds its width');
    }
    bytes.push(...my_value);
    for (let i = my_value.length; i < width; i++) bytes.push(0);
}

function push_unsigned(
    bytes: number[],
    value: number,
    width: number,
    byte_order: FixtureByteOrder
): void {
    let my_value = BigInt(value);
    const my_field = new Array<number>(width);
    for (let i = 0; i < width; i++) {
        const my_index = byte_order === 'LSF' ? i : width - i - 1;
        my_field[my_index] = Number(my_value & 0xffn);
        my_value >>= 8n;
    }
    if (my_value !== 0n) {
        throw new Error('Synthetic fixture integer exceeds its width');
    }
    bytes.push(...my_field);
}

/** Build a one-row release-119 file whose only cell is a valid strL. */
export function v119_strl_fixture(
    byte_order: FixtureByteOrder
): ArrayBuffer {
    const the_bytes: number[] = [];
    push_ascii(the_bytes, '<stata_dta><header><release>119</release>');
    push_ascii(the_bytes, `<byteorder>${byte_order}</byteorder><K>`);
    push_unsigned(the_bytes, 1, 4, byte_order);
    push_ascii(the_bytes, '</K><N>');
    push_unsigned(the_bytes, 1, 8, byte_order);
    push_ascii(the_bytes, '</N><label>');
    push_unsigned(the_bytes, 0, 2, byte_order);
    push_ascii(
        the_bytes,
        '</label><timestamp>\0</timestamp></header>'
    );

    const the_offsets = new Array<number>(14).fill(0);
    the_offsets[1] = the_bytes.length;
    push_ascii(the_bytes, '<map>');
    const my_map_payload = the_bytes.length;
    for (let i = 0; i < 14 * 8; i++) the_bytes.push(0);
    push_ascii(the_bytes, '</map>');

    the_offsets[2] = the_bytes.length;
    push_ascii(the_bytes, '<variable_types>');
    push_unsigned(the_bytes, 32_768, 2, byte_order);
    push_ascii(the_bytes, '</variable_types>');

    the_offsets[3] = the_bytes.length;
    push_ascii(the_bytes, '<varnames>');
    push_fixed(the_bytes, 'text', 129);
    push_ascii(the_bytes, '</varnames>');

    the_offsets[4] = the_bytes.length;
    push_ascii(the_bytes, '<sortlist>');
    push_unsigned(the_bytes, 0, 4, byte_order);
    push_unsigned(the_bytes, 0, 4, byte_order);
    push_ascii(the_bytes, '</sortlist>');

    the_offsets[5] = the_bytes.length;
    push_ascii(the_bytes, '<formats>');
    push_fixed(the_bytes, '%9s', 57);
    push_ascii(the_bytes, '</formats>');

    the_offsets[6] = the_bytes.length;
    push_ascii(the_bytes, '<value_label_names>');
    push_fixed(the_bytes, '', 129);
    push_ascii(the_bytes, '</value_label_names>');

    the_offsets[7] = the_bytes.length;
    push_ascii(the_bytes, '<variable_labels>');
    push_fixed(the_bytes, 'Release 119 strL', 321);
    push_ascii(the_bytes, '</variable_labels>');

    the_offsets[8] = the_bytes.length;
    push_ascii(the_bytes, '<characteristics></characteristics>');

    the_offsets[9] = the_bytes.length;
    push_ascii(the_bytes, '<data>');
    push_unsigned(the_bytes, 1, 3, byte_order);
    push_unsigned(the_bytes, 1, 5, byte_order);
    push_ascii(the_bytes, '</data>');

    the_offsets[10] = the_bytes.length;
    push_ascii(the_bytes, '<strls>GSO');
    push_unsigned(the_bytes, 1, 4, byte_order);
    push_unsigned(the_bytes, 1, 8, byte_order);
    the_bytes.push(130);
    const my_content = ASCII_ENCODER.encode(V119_STRL_VALUE);
    push_unsigned(the_bytes, my_content.length + 1, 4, byte_order);
    the_bytes.push(...my_content, 0);
    push_ascii(the_bytes, '</strls>');

    the_offsets[11] = the_bytes.length;
    push_ascii(the_bytes, '<value_labels></value_labels>');
    the_offsets[12] = the_bytes.length;
    push_ascii(the_bytes, '</stata_dta>');
    the_offsets[13] = the_bytes.length;

    const my_buffer = new Uint8Array(the_bytes).buffer;
    const my_view = new DataView(my_buffer);
    const my_little_endian = byte_order === 'LSF';
    for (let i = 0; i < the_offsets.length; i++) {
        my_view.setBigUint64(
            my_map_payload + i * 8,
            BigInt(the_offsets[i]),
            my_little_endian
        );
    }
    return my_buffer;
}
