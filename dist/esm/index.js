// src/types.ts
var FORMAT_SIGNATURES = {
  117: "<stata_dta><header><release>117</release>",
  118: "<stata_dta><header><release>118</release>",
  119: "<stata_dta><header><release>119</release>"
};
var LEGACY_FORMAT_SET = /* @__PURE__ */ new Set([113, 114, 115]);
function is_legacy_format(version) {
  return LEGACY_FORMAT_SET.has(version);
}
var V117_TYPE_CODES = {
  251: { type: "byte", width: 1 },
  252: { type: "int", width: 2 },
  253: { type: "long", width: 4 },
  254: { type: "float", width: 4 },
  255: { type: "double", width: 8 },
  32768: { type: "strL", width: 8 }
};
var V118_TYPE_CODES = {
  65530: { type: "byte", width: 1 },
  65529: { type: "int", width: 2 },
  65528: { type: "long", width: 4 },
  65527: { type: "float", width: 4 },
  65526: { type: "double", width: 8 },
  32768: { type: "strL", width: 8 }
};
var MAX_STR_WIDTH_V117 = 244;
var MAX_STR_WIDTH_V118 = 2045;
function byte_width_for_type_code(code, format_version) {
  if (format_version === 117) {
    const my_entry = V117_TYPE_CODES[code] ?? V118_TYPE_CODES[code];
    if (my_entry) return my_entry.width;
    if (code >= 1 && code <= MAX_STR_WIDTH_V117) {
      return code;
    }
  } else {
    const my_entry = V118_TYPE_CODES[code];
    if (my_entry) return my_entry.width;
    if (code >= 1 && code <= MAX_STR_WIDTH_V118) {
      return code;
    }
  }
  throw new Error(
    `Unknown type code ${code} for format v${format_version}`
  );
}
function type_code_to_dta_type(code, format_version) {
  if (format_version === 117) {
    const my_entry = V117_TYPE_CODES[code] ?? V118_TYPE_CODES[code];
    if (my_entry) return my_entry.type;
    if (code >= 1 && code <= MAX_STR_WIDTH_V117) {
      return `str${code}`;
    }
  } else {
    const my_entry = V118_TYPE_CODES[code];
    if (my_entry) return my_entry.type;
    if (code >= 1 && code <= MAX_STR_WIDTH_V118) {
      return `str${code}`;
    }
  }
  throw new Error(
    `Unknown type code ${code} for format v${format_version}`
  );
}
var LEGACY_TYPE_CODES = {
  251: { type: "byte", width: 1 },
  252: { type: "int", width: 2 },
  253: { type: "long", width: 4 },
  254: { type: "float", width: 4 },
  255: { type: "double", width: 8 }
};
var MAX_STR_WIDTH_LEGACY = 244;
function byte_width_for_legacy_type_code(code) {
  const my_entry = LEGACY_TYPE_CODES[code];
  if (my_entry) return my_entry.width;
  if (code >= 1 && code <= MAX_STR_WIDTH_LEGACY) {
    return code;
  }
  throw new Error(
    `Unknown legacy type code ${code}`
  );
}
function legacy_type_code_to_dta_type(code) {
  const my_entry = LEGACY_TYPE_CODES[code];
  if (my_entry) return my_entry.type;
  if (code >= 1 && code <= MAX_STR_WIDTH_LEGACY) {
    return `str${code}`;
  }
  throw new Error(
    `Unknown legacy type code ${code}`
  );
}

// src/header.ts
var FIELD_WIDTHS = {
  117: {
    varname: 33,
    format: 49,
    value_label_name: 33,
    variable_label: 81
  },
  118: {
    varname: 129,
    format: 57,
    value_label_name: 129,
    variable_label: 321
  },
  119: {
    varname: 129,
    format: 57,
    value_label_name: 129,
    variable_label: 321
  }
};
var SECTION_MAP_ENTRIES = 14;
var TEXT_DECODER = new TextDecoder("utf-8");
var TAG_BYTEORDER_OPEN = encode_tag("<byteorder>");
var TAG_BYTEORDER_CLOSE = encode_tag("</byteorder>");
var TAG_K_OPEN = encode_tag("<K>");
var TAG_K_CLOSE = encode_tag("</K>");
var TAG_N_OPEN = encode_tag("<N>");
var TAG_N_CLOSE = encode_tag("</N>");
var TAG_LABEL_OPEN = encode_tag("<label>");
var TAG_LABEL_CLOSE = encode_tag("</label>");
var TAG_TIMESTAMP_CLOSE = encode_tag("</timestamp>");
var TAG_MAP_OPEN = encode_tag("<map>");
var TAG_MAP_CLOSE = encode_tag("</map>");
var TAG_VARIABLE_TYPES_OPEN = encode_tag(
  "<variable_types>"
);
var TAG_VARNAMES_OPEN = encode_tag("<varnames>");
var TAG_FORMATS_OPEN = encode_tag("<formats>");
var TAG_VALUE_LABEL_NAMES_OPEN = encode_tag(
  "<value_label_names>"
);
var TAG_VARIABLE_LABELS_OPEN = encode_tag(
  "<variable_labels>"
);
function encode_tag(tag) {
  const my_buf = new Uint8Array(tag.length);
  for (let i = 0; i < tag.length; i++) {
    my_buf[i] = tag.charCodeAt(i);
  }
  return my_buf;
}
function find_bytes(haystack, needle, start) {
  const my_limit = haystack.length - needle.length;
  outer:
    for (let i = start; i <= my_limit; i++) {
      for (let j = 0; j < needle.length; j++) {
        if (haystack[i + j] !== needle[j]) {
          continue outer;
        }
      }
      return i;
    }
  return -1;
}
function read_fixed_string(bytes, offset, field_width) {
  let my_end = offset;
  const my_limit = offset + field_width;
  while (my_end < my_limit && bytes[my_end] !== 0) {
    my_end++;
  }
  return TEXT_DECODER.decode(
    bytes.subarray(offset, my_end)
  );
}
function detect_format_version(bytes) {
  for (const [my_ver_str, my_sig] of Object.entries(
    FORMAT_SIGNATURES
  )) {
    if (bytes.length < my_sig.length) continue;
    let my_match = true;
    for (let i = 0; i < my_sig.length; i++) {
      if (bytes[i] !== my_sig.charCodeAt(i)) {
        my_match = false;
        break;
      }
    }
    if (my_match) {
      return Number(my_ver_str);
    }
  }
  throw new Error(
    "Not a valid .dta file: unrecognized format signature"
  );
}
function parse_byte_order(bytes, start) {
  const my_open = find_bytes(
    bytes,
    TAG_BYTEORDER_OPEN,
    start
  );
  if (my_open === -1) {
    throw new Error("Missing <byteorder> tag");
  }
  const my_data_start = my_open + TAG_BYTEORDER_OPEN.length;
  const my_close = find_bytes(
    bytes,
    TAG_BYTEORDER_CLOSE,
    my_data_start
  );
  if (my_close === -1) {
    throw new Error("Missing </byteorder> tag");
  }
  const my_str = TEXT_DECODER.decode(
    bytes.subarray(my_data_start, my_close)
  );
  if (my_str !== "MSF" && my_str !== "LSF") {
    throw new Error(
      `Invalid byte order: "${my_str}"`
    );
  }
  return {
    byte_order: my_str,
    end: my_close + TAG_BYTEORDER_CLOSE.length
  };
}
function parse_nvar(bytes, view, little_endian, format_version, start) {
  const my_open = find_bytes(
    bytes,
    TAG_K_OPEN,
    start
  );
  if (my_open === -1) {
    throw new Error("Missing <K> tag");
  }
  const my_data_start = my_open + TAG_K_OPEN.length;
  let my_nvar;
  let my_data_end;
  if (format_version === 119) {
    my_nvar = view.getUint32(
      my_data_start,
      little_endian
    );
    my_data_end = my_data_start + 4;
  } else {
    my_nvar = view.getUint16(
      my_data_start,
      little_endian
    );
    my_data_end = my_data_start + 2;
  }
  return { nvar: my_nvar, end: my_data_end };
}
function parse_nobs(bytes, view, little_endian, format_version, start) {
  const my_open = find_bytes(
    bytes,
    TAG_N_OPEN,
    start
  );
  if (my_open === -1) {
    throw new Error("Missing <N> tag");
  }
  const my_data_start = my_open + TAG_N_OPEN.length;
  let my_nobs;
  let my_data_end;
  if (format_version === 117 || format_version === 118) {
    my_nobs = view.getUint32(
      my_data_start,
      little_endian
    );
    my_data_end = my_data_start + 4;
  } else {
    const my_big_nobs = view.getBigUint64(
      my_data_start,
      little_endian
    );
    if (my_big_nobs > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new Error(
        "Dataset too large: observation count exceeds JavaScript safe integer limit"
      );
    }
    my_nobs = Number(my_big_nobs);
    my_data_end = my_data_start + 8;
  }
  return { nobs: my_nobs, end: my_data_end };
}
function parse_dataset_label(bytes, view, little_endian, format_version, start) {
  const my_open = find_bytes(
    bytes,
    TAG_LABEL_OPEN,
    start
  );
  if (my_open === -1) {
    throw new Error("Missing <label> tag");
  }
  const my_data_start = my_open + TAG_LABEL_OPEN.length;
  let my_str_len;
  let my_str_start;
  if (format_version === 117) {
    my_str_len = view.getUint8(my_data_start);
    my_str_start = my_data_start + 1;
  } else {
    my_str_len = view.getUint16(
      my_data_start,
      little_endian
    );
    my_str_start = my_data_start + 2;
  }
  const my_label = TEXT_DECODER.decode(
    bytes.subarray(my_str_start, my_str_start + my_str_len)
  );
  const my_close = find_bytes(
    bytes,
    TAG_LABEL_CLOSE,
    my_str_start + my_str_len
  );
  if (my_close === -1) {
    throw new Error("Missing </label> tag");
  }
  return {
    dataset_label: my_label,
    end: my_close + TAG_LABEL_CLOSE.length
  };
}
var SECTION_OFFSET_KEYS = [
  "stata_data",
  "map",
  "variable_types",
  "varnames",
  "sortlist",
  "formats",
  "value_label_names",
  "variable_labels",
  "characteristics",
  "data",
  "strls",
  "value_labels",
  "stata_data_close",
  "end_of_file"
];
function parse_section_map(bytes, view, little_endian, start) {
  const my_open = find_bytes(
    bytes,
    TAG_MAP_OPEN,
    start
  );
  if (my_open === -1) {
    throw new Error("Missing <map> tag");
  }
  const my_data_start = my_open + TAG_MAP_OPEN.length;
  const my_offsets = {};
  for (let i = 0; i < SECTION_MAP_ENTRIES; i++) {
    const my_val = Number(view.getBigUint64(
      my_data_start + i * 8,
      little_endian
    ));
    my_offsets[SECTION_OFFSET_KEYS[i]] = my_val;
  }
  return my_offsets;
}
function parse_variable_types(bytes, view, little_endian, offsets, nvar) {
  const my_tag_pos = find_bytes(
    bytes,
    TAG_VARIABLE_TYPES_OPEN,
    offsets.variable_types
  );
  if (my_tag_pos === -1) {
    throw new Error("Missing <variable_types> tag");
  }
  const my_data_start = my_tag_pos + TAG_VARIABLE_TYPES_OPEN.length;
  const my_required_bytes = nvar * 2;
  if (my_data_start + my_required_bytes > bytes.length) {
    throw new Error(
      "Corrupt .dta file: variable_types section truncated"
    );
  }
  const the_type_codes = [];
  for (let i = 0; i < nvar; i++) {
    the_type_codes.push(
      view.getUint16(
        my_data_start + i * 2,
        little_endian
      )
    );
  }
  return the_type_codes;
}
function parse_fixed_string_section(bytes, tag, search_start, nvar, field_width) {
  const my_tag_pos = find_bytes(
    bytes,
    tag,
    search_start
  );
  if (my_tag_pos === -1) {
    throw new Error(
      `Missing section tag at offset ${search_start}`
    );
  }
  const my_data_start = my_tag_pos + tag.length;
  const my_required_bytes = nvar * field_width;
  if (my_data_start + my_required_bytes > bytes.length) {
    throw new Error(
      "Corrupt .dta file: section truncated"
    );
  }
  const the_strings = [];
  for (let i = 0; i < nvar; i++) {
    the_strings.push(
      read_fixed_string(
        bytes,
        my_data_start + i * field_width,
        field_width
      )
    );
  }
  return the_strings;
}
function parse_metadata(buffer) {
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  const format_version = detect_format_version(bytes);
  const my_widths = FIELD_WIDTHS[format_version];
  const { byte_order, end: my_after_byteorder } = parse_byte_order(bytes, 0);
  const little_endian = byte_order === "LSF";
  const { nvar, end: my_after_k } = parse_nvar(
    bytes,
    view,
    little_endian,
    format_version,
    my_after_byteorder
  );
  const { nobs, end: my_after_n } = parse_nobs(
    bytes,
    view,
    little_endian,
    format_version,
    my_after_k
  );
  const { dataset_label, end: my_after_label } = parse_dataset_label(
    bytes,
    view,
    little_endian,
    format_version,
    my_after_n
  );
  const my_ts_close = find_bytes(
    bytes,
    TAG_TIMESTAMP_CLOSE,
    my_after_label
  );
  if (my_ts_close === -1) {
    throw new Error("Missing </timestamp> tag");
  }
  const section_offsets = parse_section_map(
    bytes,
    view,
    little_endian,
    my_ts_close
  );
  const the_type_codes = parse_variable_types(
    bytes,
    view,
    little_endian,
    section_offsets,
    nvar
  );
  const the_varnames = parse_fixed_string_section(
    bytes,
    TAG_VARNAMES_OPEN,
    section_offsets.varnames,
    nvar,
    my_widths.varname
  );
  const the_formats = parse_fixed_string_section(
    bytes,
    TAG_FORMATS_OPEN,
    section_offsets.formats,
    nvar,
    my_widths.format
  );
  const the_value_label_names = parse_fixed_string_section(
    bytes,
    TAG_VALUE_LABEL_NAMES_OPEN,
    section_offsets.value_label_names,
    nvar,
    my_widths.value_label_name
  );
  const the_variable_labels = parse_fixed_string_section(
    bytes,
    TAG_VARIABLE_LABELS_OPEN,
    section_offsets.variable_labels,
    nvar,
    my_widths.variable_label
  );
  let my_running_offset = 0;
  const the_variables = [];
  for (let i = 0; i < nvar; i++) {
    const my_code = the_type_codes[i];
    const my_width = byte_width_for_type_code(
      my_code,
      format_version
    );
    the_variables.push({
      name: the_varnames[i],
      type: type_code_to_dta_type(
        my_code,
        format_version
      ),
      type_code: my_code,
      format: the_formats[i],
      label: the_variable_labels[i],
      value_label_name: the_value_label_names[i],
      byte_width: my_width,
      byte_offset: my_running_offset
    });
    my_running_offset += my_width;
  }
  return {
    format_version,
    byte_order,
    nvar,
    nobs,
    dataset_label,
    variables: the_variables,
    section_offsets,
    obs_length: my_running_offset
  };
}

// src/legacy-header.ts
var HEADER_FIXED_SIZE = 109;
var VARNAME_WIDTH = 33;
var VALUE_LABEL_NAME_WIDTH = 33;
var VARIABLE_LABEL_WIDTH = 81;
var SORTLIST_ENTRY_WIDTH = 2;
var FORMAT_WIDTH_113 = 12;
var FORMAT_WIDTH_114_115 = 49;
var TEXT_DECODER2 = new TextDecoder("windows-1252");
function read_fixed_string2(bytes, offset, field_width) {
  let my_end = offset;
  const my_limit = offset + field_width;
  while (my_end < my_limit && bytes[my_end] !== 0) {
    my_end++;
  }
  return TEXT_DECODER2.decode(
    bytes.subarray(offset, my_end)
  );
}
function legacy_metadata_buffer_size(nvar, format_version) {
  const my_fmt_width = format_version === 113 ? FORMAT_WIDTH_113 : FORMAT_WIDTH_114_115;
  const my_sections_size = nvar * 1 + nvar * VARNAME_WIDTH + (nvar + 1) * SORTLIST_ENTRY_WIDTH + nvar * my_fmt_width + nvar * VALUE_LABEL_NAME_WIDTH + nvar * VARIABLE_LABEL_WIDTH;
  return HEADER_FIXED_SIZE + my_sections_size + 65536;
}
function scan_expansion_fields(view, little_endian, start, buffer_length) {
  let pos = start;
  while (pos + 5 <= buffer_length) {
    const my_data_type = view.getUint8(pos);
    const my_len = view.getInt32(pos + 1, little_endian);
    pos += 5;
    if (my_data_type === 0 && my_len === 0) {
      return pos;
    }
    pos += my_len;
  }
  return pos;
}
function parse_legacy_metadata(buffer, file_size) {
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  const my_version_byte = bytes[0];
  if (my_version_byte !== 113 && my_version_byte !== 114 && my_version_byte !== 115) {
    throw new Error(
      `Not a legacy .dta file: version byte ${my_version_byte}`
    );
  }
  const format_version = my_version_byte;
  const my_byte_order_code = bytes[1];
  if (my_byte_order_code !== 1 && my_byte_order_code !== 2) {
    throw new Error(
      `Invalid byte order code: ${my_byte_order_code}`
    );
  }
  const byte_order = my_byte_order_code === 1 ? "MSF" : "LSF";
  const little_endian = byte_order === "LSF";
  const nvar = view.getUint16(4, little_endian);
  const nobs = view.getInt32(6, little_endian);
  if (nobs < 0) {
    throw new Error(
      `Invalid observation count: ${nobs}`
    );
  }
  const dataset_label = read_fixed_string2(bytes, 10, 81);
  const my_fmt_width = format_version === 113 ? FORMAT_WIDTH_113 : FORMAT_WIDTH_114_115;
  let pos = HEADER_FIXED_SIZE;
  const my_variable_types_offset = pos;
  const the_type_codes = [];
  for (let i = 0; i < nvar; i++) {
    the_type_codes.push(bytes[pos + i]);
  }
  pos += nvar;
  const my_varnames_offset = pos;
  const the_varnames = [];
  for (let i = 0; i < nvar; i++) {
    the_varnames.push(
      read_fixed_string2(
        bytes,
        pos + i * VARNAME_WIDTH,
        VARNAME_WIDTH
      )
    );
  }
  pos += nvar * VARNAME_WIDTH;
  const my_sortlist_offset = pos;
  pos += (nvar + 1) * SORTLIST_ENTRY_WIDTH;
  const my_formats_offset = pos;
  const the_formats = [];
  for (let i = 0; i < nvar; i++) {
    the_formats.push(
      read_fixed_string2(
        bytes,
        pos + i * my_fmt_width,
        my_fmt_width
      )
    );
  }
  pos += nvar * my_fmt_width;
  const my_value_label_names_offset = pos;
  const the_value_label_names = [];
  for (let i = 0; i < nvar; i++) {
    the_value_label_names.push(
      read_fixed_string2(
        bytes,
        pos + i * VALUE_LABEL_NAME_WIDTH,
        VALUE_LABEL_NAME_WIDTH
      )
    );
  }
  pos += nvar * VALUE_LABEL_NAME_WIDTH;
  const my_variable_labels_offset = pos;
  const the_variable_labels = [];
  for (let i = 0; i < nvar; i++) {
    the_variable_labels.push(
      read_fixed_string2(
        bytes,
        pos + i * VARIABLE_LABEL_WIDTH,
        VARIABLE_LABEL_WIDTH
      )
    );
  }
  pos += nvar * VARIABLE_LABEL_WIDTH;
  const my_expansion_offset = pos;
  const my_data_offset = scan_expansion_fields(
    view,
    little_endian,
    pos,
    buffer.byteLength
  );
  let my_running_offset = 0;
  const the_variables = [];
  for (let i = 0; i < nvar; i++) {
    const my_code = the_type_codes[i];
    const my_width = byte_width_for_legacy_type_code(my_code);
    the_variables.push({
      name: the_varnames[i],
      type: legacy_type_code_to_dta_type(my_code),
      type_code: my_code,
      format: the_formats[i],
      label: the_variable_labels[i],
      value_label_name: the_value_label_names[i],
      byte_width: my_width,
      byte_offset: my_running_offset
    });
    my_running_offset += my_width;
  }
  const obs_length = my_running_offset;
  const my_value_labels_offset = Number(
    BigInt(my_data_offset) + BigInt(nobs) * BigInt(obs_length)
  );
  const section_offsets = {
    stata_data: 0,
    map: 0,
    variable_types: my_variable_types_offset,
    varnames: my_varnames_offset,
    sortlist: my_sortlist_offset,
    formats: my_formats_offset,
    value_label_names: my_value_label_names_offset,
    variable_labels: my_variable_labels_offset,
    characteristics: my_expansion_offset,
    data: my_data_offset,
    strls: my_value_labels_offset,
    value_labels: my_value_labels_offset,
    stata_data_close: file_size,
    end_of_file: file_size
  };
  return {
    format_version,
    byte_order,
    nvar,
    nobs,
    dataset_label,
    variables: the_variables,
    section_offsets,
    obs_length
  };
}

// src/missing-values.ts
var BYTE_MISSING_DOT = 101;
var BYTE_MISSING_Z = 127;
var INT_MISSING_DOT = 32741;
var INT_MISSING_Z = 32767;
var LONG_MISSING_DOT = 2147483621;
var LONG_MISSING_Z = 2147483647;
var FLOAT_MISSING_DOT_RAW = 2130706432;
var FLOAT_MISSING_STEP_RAW = 2048;
var FLOAT_MISSING_Z_RAW = FLOAT_MISSING_DOT_RAW + 26 * FLOAT_MISSING_STEP_RAW;
var DOUBLE_PREFIX_HI = 32736;
var DOUBLE_LETTER_MAX = 26;
function bytes_to_double(bytes) {
  const my_buf = new ArrayBuffer(8);
  const my_view = new DataView(my_buf);
  bytes.forEach((my_byte, my_index) => {
    my_view.setUint8(my_index, my_byte);
  });
  return my_view.getFloat64(0, false);
}
var STATA_MISSING = bytes_to_double(
  [127, 224, 0, 0, 0, 0, 0, 0]
);
var STATA_MISSING_A = bytes_to_double(
  [127, 224, 1, 0, 0, 0, 0, 0]
);
var STATA_MISSING_B = bytes_to_double(
  [127, 224, 2, 0, 0, 0, 0, 0]
);
var STATA_MISSING_Z = bytes_to_double(
  [127, 224, 26, 0, 0, 0, 0, 0]
);
function classify_missing_from_offset(offset) {
  if (offset < 0 || offset > 26) {
    return null;
  }
  if (offset === 0) {
    return ".";
  }
  return `.${String.fromCharCode(96 + offset)}`;
}
function classify_integer_missing(value, dot, z) {
  if (value < dot || value > z) {
    return null;
  }
  return classify_missing_from_offset(value - dot);
}
function classify_float_raw_missing(raw_value) {
  if (raw_value < FLOAT_MISSING_DOT_RAW || raw_value > FLOAT_MISSING_Z_RAW) {
    return null;
  }
  const my_delta = raw_value - FLOAT_MISSING_DOT_RAW;
  if (my_delta % FLOAT_MISSING_STEP_RAW !== 0) {
    return null;
  }
  return classify_missing_from_offset(
    my_delta / FLOAT_MISSING_STEP_RAW
  );
}
function classify_double_big_endian_parts(hi_word, lo_word) {
  if (hi_word >>> 16 !== DOUBLE_PREFIX_HI) {
    return null;
  }
  const my_letter = hi_word >>> 8 & 255;
  if (my_letter > DOUBLE_LETTER_MAX) {
    return null;
  }
  if ((hi_word & 255) !== 0 || lo_word !== 0) {
    return null;
  }
  return classify_missing_from_offset(my_letter);
}
function classify_double_js_missing(value) {
  const my_buf = new ArrayBuffer(8);
  const my_view = new DataView(my_buf);
  my_view.setFloat64(0, value, false);
  return classify_double_big_endian_parts(
    my_view.getUint32(0, false),
    my_view.getUint32(4, false)
  );
}
function make_missing_value(missing_type) {
  return {
    kind: "missing",
    missing_type
  };
}
function is_missing_value_object(value) {
  return typeof value === "object" && value !== null && value.kind === "missing" && typeof value.missing_type === "string";
}
function classify_raw_float_missing(raw_value) {
  return classify_float_raw_missing(raw_value);
}
function classify_raw_double_missing_at(view, offset, little_endian) {
  const my_hi_word = little_endian ? view.getUint32(offset + 4, true) : view.getUint32(offset, false);
  const my_lo_word = little_endian ? view.getUint32(offset, true) : view.getUint32(offset + 4, false);
  return classify_double_big_endian_parts(
    my_hi_word,
    my_lo_word
  );
}
function is_missing_value(value, type) {
  return classify_missing_value(value, type) !== null;
}
function missing_type_to_label_key(missing_type) {
  if (missing_type === ".") {
    return LONG_MISSING_DOT;
  }
  const my_offset = missing_type.charCodeAt(1) - 96;
  return LONG_MISSING_DOT + my_offset;
}
function classify_missing_value(value, type) {
  switch (type) {
    case "byte":
      return classify_integer_missing(
        value,
        BYTE_MISSING_DOT,
        BYTE_MISSING_Z
      );
    case "int":
      return classify_integer_missing(
        value,
        INT_MISSING_DOT,
        INT_MISSING_Z
      );
    case "long":
      return classify_integer_missing(
        value,
        LONG_MISSING_DOT,
        LONG_MISSING_Z
      );
    case "float":
      return classify_float_raw_missing(
        new DataView(
          new Float32Array([value]).buffer
        ).getUint32(0, true)
      );
    case "double":
    default:
      return classify_double_js_missing(value);
  }
}

// src/data-reader.ts
var DATA_TAG = "<data>";
var DATA_TAG_LENGTH = DATA_TAG.length;
var UTF8_DECODER = new TextDecoder("utf-8");
function read_fixed_string3(bytes, offset, width) {
  let my_end = offset;
  const my_limit = offset + width;
  while (my_end < my_limit && bytes[my_end] !== 0) {
    my_end++;
  }
  return UTF8_DECODER.decode(
    bytes.subarray(offset, my_end)
  );
}
function read_cell(view, bytes, offset, type, width, little_endian) {
  switch (type) {
    case "byte": {
      const my_val = view.getInt8(offset);
      const my_missing_type = classify_missing_value(
        my_val,
        "byte"
      );
      if (my_missing_type) {
        return make_missing_value(my_missing_type);
      }
      return my_val;
    }
    case "int": {
      const my_val = view.getInt16(
        offset,
        little_endian
      );
      const my_missing_type = classify_missing_value(
        my_val,
        "int"
      );
      if (my_missing_type) {
        return make_missing_value(my_missing_type);
      }
      return my_val;
    }
    case "long": {
      const my_val = view.getInt32(
        offset,
        little_endian
      );
      const my_missing_type = classify_missing_value(
        my_val,
        "long"
      );
      if (my_missing_type) {
        return make_missing_value(my_missing_type);
      }
      return my_val;
    }
    case "float": {
      const my_raw = view.getUint32(
        offset,
        little_endian
      );
      const my_missing_type = classify_raw_float_missing(my_raw);
      if (my_missing_type) {
        return make_missing_value(my_missing_type);
      }
      return view.getFloat32(
        offset,
        little_endian
      );
    }
    case "double": {
      const my_missing_type = classify_raw_double_missing_at(
        view,
        offset,
        little_endian
      );
      if (my_missing_type) {
        return make_missing_value(my_missing_type);
      }
      return view.getFloat64(
        offset,
        little_endian
      );
    }
    case "strL": {
      return "__strl__";
    }
    default: {
      return read_fixed_string3(
        bytes,
        offset,
        width
      );
    }
  }
}
function read_rows_from_view(view, bytes, metadata, row_base_offset, start, count, col_start, col_end) {
  if (metadata.nobs === 0 || start < 0 || count <= 0 || start >= metadata.nobs) {
    return [];
  }
  const my_actual_count = Math.min(
    count,
    metadata.nobs - start
  );
  if (my_actual_count <= 0) return [];
  const my_col_start = Math.max(0, col_start ?? 0);
  const my_col_end = Math.min(
    metadata.nvar,
    col_end ?? metadata.nvar
  );
  if (my_col_start >= my_col_end) {
    return [];
  }
  const little_endian = metadata.byte_order === "LSF";
  const the_rows = [];
  for (let i = 0; i < my_actual_count; i++) {
    const my_row_offset = row_base_offset + i * metadata.obs_length;
    const my_row = [];
    for (let j = my_col_start; j < my_col_end; j++) {
      const my_var = metadata.variables[j];
      const my_cell_offset = my_row_offset + my_var.byte_offset;
      my_row.push(
        read_cell(
          view,
          bytes,
          my_cell_offset,
          my_var.type,
          my_var.byte_width,
          little_endian
        )
      );
    }
    the_rows.push(my_row);
  }
  return the_rows;
}
function read_rows_from_buffer(buffer, metadata, start, count, col_start, col_end) {
  const view = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  const my_tag_length = is_legacy_format(
    metadata.format_version
  ) ? 0 : DATA_TAG_LENGTH;
  const my_data_start = metadata.section_offsets.data + my_tag_length;
  return read_rows_from_view(
    view,
    bytes,
    metadata,
    my_data_start + start * metadata.obs_length,
    start,
    count,
    col_start,
    col_end
  );
}
function read_rows_from_data_buffer(buffer, metadata, start, count, col_start, col_end) {
  const view = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  return read_rows_from_view(
    view,
    bytes,
    metadata,
    0,
    start,
    count,
    col_start,
    col_end
  );
}

// src/strl-reader.ts
var GSO_MARKER = [71, 83, 79];
var STRLS_TAG = "<strls>";
var STRLS_TAG_LENGTH = STRLS_TAG.length;
var UTF8_DECODER2 = new TextDecoder("utf-8");
function build_gso_index(buffer, metadata, base_offset = 0) {
  const my_index = /* @__PURE__ */ new Map();
  const my_has_strl = metadata.variables.some(
    (v) => v.type === "strL"
  );
  if (!my_has_strl) return my_index;
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  const little_endian = metadata.byte_order === "LSF";
  let pos = metadata.section_offsets.strls - base_offset + STRLS_TAG_LENGTH;
  const my_section_end = metadata.section_offsets.value_labels - base_offset;
  while (pos + 3 <= my_section_end) {
    if (bytes[pos] !== GSO_MARKER[0] || bytes[pos + 1] !== GSO_MARKER[1] || bytes[pos + 2] !== GSO_MARKER[2]) {
      break;
    }
    pos += 3;
    const my_v = view.getUint32(pos, little_endian);
    pos += 4;
    let my_o;
    if (metadata.format_version === 117) {
      my_o = view.getUint32(pos, little_endian);
      pos += 4;
    } else {
      if (little_endian) {
        my_o = view.getUint32(pos, true);
        const my_hi = view.getUint32(
          pos + 4,
          true
        );
        if (my_hi !== 0) {
          throw new Error(
            "strL observation number exceeds 32-bit range"
          );
        }
        pos += 8;
      } else {
        const my_hi = view.getUint32(pos, false);
        if (my_hi !== 0) {
          throw new Error(
            "strL observation number exceeds 32-bit range"
          );
        }
        const my_lo = view.getUint32(
          pos + 4,
          false
        );
        my_o = my_lo;
        pos += 8;
      }
    }
    const my_type = bytes[pos];
    pos += 1;
    const my_len = view.getUint32(pos, little_endian);
    pos += 4;
    const my_key = my_v + ":" + my_o;
    my_index.set(my_key, {
      content_offset: pos + base_offset,
      content_length: my_len,
      type: my_type
    });
    pos += my_len;
  }
  return my_index;
}
function resolve_strl(buffer, metadata, gso_index, pointer_offset) {
  const view = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  const my_pointer = read_strl_pointer(
    view,
    metadata,
    pointer_offset
  );
  if (!my_pointer) return "";
  const my_key = my_pointer.v + ":" + my_pointer.o;
  const my_entry = gso_index.get(my_key);
  if (!my_entry) return null;
  return decode_gso_entry(bytes, my_entry);
}
function read_strl_pointer(view, metadata, pointer_offset) {
  const little_endian = metadata.byte_order === "LSF";
  let my_v;
  let my_o;
  if (metadata.format_version === 117) {
    my_v = view.getUint32(
      pointer_offset,
      little_endian
    );
    my_o = view.getUint32(
      pointer_offset + 4,
      little_endian
    );
  } else if (little_endian) {
    my_v = view.getUint16(pointer_offset, true);
    my_o = view.getUint32(
      pointer_offset + 2,
      true
    );
  } else {
    my_v = view.getUint16(pointer_offset, false);
    const my_hi = view.getUint16(
      pointer_offset + 2,
      false
    );
    const my_lo = view.getUint32(
      pointer_offset + 4,
      false
    );
    my_o = my_hi * 4294967296 + my_lo;
  }
  if (my_v === 0 && my_o === 0) {
    return null;
  }
  return { v: my_v, o: my_o };
}
function decode_gso_entry(bytes, entry) {
  if (entry.type === 130) {
    const my_str_len = entry.content_length > 0 ? entry.content_length - 1 : 0;
    return UTF8_DECODER2.decode(
      bytes.subarray(
        entry.content_offset,
        entry.content_offset + my_str_len
      )
    );
  }
  return UTF8_DECODER2.decode(
    bytes.subarray(
      entry.content_offset,
      entry.content_offset + entry.content_length
    )
  );
}

// src/value-labels.ts
var VALUE_LABELS_TAG = "<value_labels>";
var VALUE_LABELS_TAG_LENGTH = VALUE_LABELS_TAG.length;
var LBL_OPEN_TAG = "<lbl>";
var LBL_OPEN_TAG_LENGTH = LBL_OPEN_TAG.length;
var LBL_CLOSE_TAG_LENGTH = 6;
var LABEL_NAME_WIDTH = {
  113: 33,
  114: 33,
  115: 33,
  117: 33,
  118: 129,
  119: 129
};
var PADDING_BYTES = 3;
var UTF8_DECODER3 = new TextDecoder("utf-8");
function parse_label_entry_payload(bytes, view, little_endian, pos, entry_end) {
  if (pos + 8 > entry_end) {
    throw new Error(
      "Corrupt value label table: truncated header"
    );
  }
  const my_n = view.getInt32(pos, little_endian);
  pos += 4;
  const my_txt_len = view.getInt32(pos, little_endian);
  pos += 4;
  if (my_n < 0 || my_txt_len < 0) {
    throw new Error(
      `Corrupt value label table: negative count or text length (n=${my_n}, txt_len=${my_txt_len})`
    );
  }
  if (pos + my_n * 8 + my_txt_len > entry_end) {
    throw new Error(
      "Corrupt value label table: payload exceeds entry bounds"
    );
  }
  const the_offsets = [];
  for (let i = 0; i < my_n; i++) {
    the_offsets.push(
      view.getInt32(pos, little_endian)
    );
    pos += 4;
  }
  const the_values = [];
  for (let i = 0; i < my_n; i++) {
    the_values.push(
      view.getInt32(pos, little_endian)
    );
    pos += 4;
  }
  const my_text_start = pos;
  const my_label_map = /* @__PURE__ */ new Map();
  for (let i = 0; i < my_n; i++) {
    if (the_offsets[i] < 0 || the_offsets[i] >= my_txt_len) {
      continue;
    }
    const my_str_start = my_text_start + the_offsets[i];
    let my_str_end = my_str_start;
    const my_str_limit = my_text_start + my_txt_len;
    while (my_str_end < my_str_limit && bytes[my_str_end] !== 0) {
      my_str_end++;
    }
    const my_label = UTF8_DECODER3.decode(
      bytes.subarray(my_str_start, my_str_end)
    );
    my_label_map.set(the_values[i], my_label);
  }
  return {
    label_map: my_label_map,
    next_pos: my_text_start + my_txt_len
  };
}
function read_label_name(bytes, pos, name_width) {
  let my_end = pos;
  const my_limit = pos + name_width;
  while (my_end < my_limit && bytes[my_end] !== 0) {
    my_end++;
  }
  return UTF8_DECODER3.decode(
    bytes.subarray(pos, my_end)
  );
}
function parse_modern_entries(bytes, view, little_endian, name_width, start_pos, section_end) {
  const my_result = /* @__PURE__ */ new Map();
  let pos = start_pos;
  while (pos + LBL_OPEN_TAG_LENGTH <= section_end) {
    if (bytes[pos] !== 60 || bytes[pos + 1] !== 108 || bytes[pos + 2] !== 98 || bytes[pos + 3] !== 108 || bytes[pos + 4] !== 62) {
      break;
    }
    pos += LBL_OPEN_TAG_LENGTH;
    pos += 4;
    const my_label_name = read_label_name(
      bytes,
      pos,
      name_width
    );
    pos += name_width;
    pos += PADDING_BYTES;
    const { label_map, next_pos } = parse_label_entry_payload(
      bytes,
      view,
      little_endian,
      pos,
      section_end
    );
    my_result.set(my_label_name, label_map);
    pos = next_pos + LBL_CLOSE_TAG_LENGTH;
  }
  return my_result;
}
function parse_legacy_entries(bytes, view, little_endian, name_width, start_pos, section_end) {
  const my_result = /* @__PURE__ */ new Map();
  let pos = start_pos;
  while (pos + 4 <= section_end) {
    const my_table_len = view.getInt32(
      pos,
      little_endian
    );
    if (my_table_len <= 0) break;
    pos += 4;
    const my_label_name = read_label_name(
      bytes,
      pos,
      name_width
    );
    pos += name_width;
    pos += PADDING_BYTES;
    const { label_map, next_pos } = parse_label_entry_payload(
      bytes,
      view,
      little_endian,
      pos,
      section_end
    );
    my_result.set(my_label_name, label_map);
    pos = next_pos;
  }
  return my_result;
}
function parse_value_labels(buffer, metadata, base_offset = 0) {
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  const little_endian = metadata.byte_order === "LSF";
  const my_name_width = LABEL_NAME_WIDTH[metadata.format_version];
  const my_legacy = is_legacy_format(
    metadata.format_version
  );
  const my_tag_skip = my_legacy ? 0 : VALUE_LABELS_TAG_LENGTH;
  const my_start_pos = metadata.section_offsets.value_labels - base_offset + my_tag_skip;
  const my_section_end = metadata.section_offsets.stata_data_close - base_offset;
  if (my_legacy) {
    return parse_legacy_entries(
      bytes,
      view,
      little_endian,
      my_name_width,
      my_start_pos,
      my_section_end
    );
  }
  return parse_modern_entries(
    bytes,
    view,
    little_endian,
    my_name_width,
    my_start_pos,
    my_section_end
  );
}

// src/display-format.ts
var STATA_EPOCH_YEAR = 1960;
var STATA_EPOCH_MONTH = 0;
var STATA_EPOCH_DAY = 1;
var MONTH_ABBREVS = [
  "jan",
  "feb",
  "mar",
  "apr",
  "may",
  "jun",
  "jul",
  "aug",
  "sep",
  "oct",
  "nov",
  "dec"
];
var MS_PER_SECOND = 1e3;
var MS_PER_MINUTE = 60 * MS_PER_SECOND;
var MS_PER_HOUR = 60 * MS_PER_MINUTE;
var MS_PER_DAY = 24 * MS_PER_HOUR;
var NUMERIC_FORMAT_RE = /^(\d+)\.(\d+)(f|g|e)(c?)$/;
function apply_display_format(value, format) {
  if (value === null) return null;
  if (typeof value === "string") return value;
  const my_trimmed = format.replace(/^%-?[+0]?/, "").replace(/^%/, "");
  if (my_trimmed.length === 0) return String(value);
  if (my_trimmed.endsWith("s")) return String(value);
  if (my_trimmed.startsWith("t")) {
    return format_date_time(value, my_trimmed);
  }
  const my_match = NUMERIC_FORMAT_RE.exec(my_trimmed);
  if (!my_match) return String(value);
  const my_decimals = parseInt(my_match[2], 10);
  const my_type = my_match[3];
  const my_use_commas = my_match[4] === "c";
  switch (my_type) {
    case "f":
      return format_fixed(
        value,
        my_decimals,
        my_use_commas
      );
    case "g":
      return format_general(
        value,
        my_use_commas
      );
    case "e":
      return format_scientific(value, my_decimals);
    default:
      return String(value);
  }
}
function format_fixed(value, decimals, use_commas) {
  const my_str = value.toFixed(decimals);
  if (!use_commas) return my_str;
  return add_thousand_separators(my_str);
}
function format_general(value, use_commas) {
  const my_str = String(value);
  if (!use_commas) return my_str;
  return add_thousand_separators(my_str);
}
function format_scientific(value, decimals) {
  const my_raw = value.toExponential(decimals);
  return my_raw.replace(
    /e([+-])(\d)$/,
    "e$10$2"
  );
}
function add_thousand_separators(str) {
  const my_dot_index = str.indexOf(".");
  const my_int_part = my_dot_index >= 0 ? str.substring(0, my_dot_index) : str;
  const my_dec_part = my_dot_index >= 0 ? str.substring(my_dot_index) : "";
  const my_is_negative = my_int_part.startsWith("-");
  const my_digits = my_is_negative ? my_int_part.substring(1) : my_int_part;
  const the_parts = [];
  const my_len = my_digits.length;
  for (let i = my_len - 1; i >= 0; i--) {
    const my_pos_from_right = my_len - 1 - i;
    if (my_pos_from_right > 0 && my_pos_from_right % 3 === 0) {
      the_parts.push(",");
    }
    the_parts.push(my_digits[i]);
  }
  the_parts.reverse();
  const my_prefix = my_is_negative ? "-" : "";
  return my_prefix + the_parts.join("") + my_dec_part;
}
function format_date_time(value, format_code) {
  switch (format_code) {
    case "td":
      return format_td(value);
    case "tc":
      return format_tc(value);
    case "tw":
      return format_tw(value);
    case "tm":
      return format_tm(value);
    case "tq":
      return format_tq(value);
    case "ty":
      return String(value);
    default:
      return String(value);
  }
}
function format_td(days_since_epoch) {
  const my_date = new Date(Date.UTC(
    STATA_EPOCH_YEAR,
    STATA_EPOCH_MONTH,
    STATA_EPOCH_DAY + days_since_epoch
  ));
  const my_day = String(my_date.getUTCDate()).padStart(2, "0");
  const my_month = MONTH_ABBREVS[my_date.getUTCMonth()];
  const my_year = my_date.getUTCFullYear();
  return `${my_day}${my_month}${my_year}`;
}
function format_tc(ms_since_epoch) {
  const my_total_days = Math.floor(
    ms_since_epoch / MS_PER_DAY
  );
  const my_remainder_ms = ms_since_epoch - my_total_days * MS_PER_DAY;
  const my_date_str = format_td(my_total_days);
  const my_hours = Math.floor(
    my_remainder_ms / MS_PER_HOUR
  );
  const my_minutes = Math.floor(
    my_remainder_ms % MS_PER_HOUR / MS_PER_MINUTE
  );
  const my_seconds = Math.floor(
    my_remainder_ms % MS_PER_MINUTE / MS_PER_SECOND
  );
  const my_hh = String(my_hours).padStart(2, "0");
  const my_mm = String(my_minutes).padStart(2, "0");
  const my_ss = String(my_seconds).padStart(2, "0");
  return `${my_date_str} ${my_hh}:${my_mm}:${my_ss}`;
}
function format_tw(weeks_since_epoch) {
  const my_year = STATA_EPOCH_YEAR + Math.floor(weeks_since_epoch / 52);
  let my_week = weeks_since_epoch % 52 + 1;
  if (my_week <= 0) my_week += 52;
  return `${my_year}w${my_week}`;
}
function format_tm(months_since_epoch) {
  const my_year = STATA_EPOCH_YEAR + Math.floor(months_since_epoch / 12);
  let my_month = months_since_epoch % 12 + 1;
  if (my_month <= 0) my_month += 12;
  return `${my_year}m${my_month}`;
}
function format_tq(quarters_since_epoch) {
  const my_year = STATA_EPOCH_YEAR + Math.floor(quarters_since_epoch / 4);
  let my_quarter = quarters_since_epoch % 4 + 1;
  if (my_quarter <= 0) my_quarter += 4;
  return `${my_year}q${my_quarter}`;
}
export {
  STATA_MISSING_B,
  apply_display_format,
  build_gso_index,
  classify_missing_value,
  classify_raw_double_missing_at,
  classify_raw_float_missing,
  decode_gso_entry,
  is_legacy_format,
  is_missing_value,
  is_missing_value_object,
  legacy_metadata_buffer_size,
  make_missing_value,
  missing_type_to_label_key,
  parse_legacy_metadata,
  parse_metadata,
  parse_value_labels,
  read_rows_from_buffer,
  read_rows_from_data_buffer,
  read_strl_pointer,
  resolve_strl
};
