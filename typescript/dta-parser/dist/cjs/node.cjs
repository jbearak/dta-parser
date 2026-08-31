var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// src/node.ts
var node_exports = {};
__export(node_exports, {
  DtaFile: () => DtaFile,
  STATA_MISSING_B: () => STATA_MISSING_B,
  addStataNote: () => addStataNote,
  apply_display_format: () => apply_display_format,
  classify_missing_value: () => classify_missing_value,
  classify_raw_double_missing_at: () => classify_raw_double_missing_at,
  classify_raw_float_missing: () => classify_raw_float_missing,
  dropStataCharacteristics: () => dropStataCharacteristics,
  dropStataNotes: () => dropStataNotes,
  getStataCharacteristic: () => getStataCharacteristic,
  getStataNote: () => getStataNote,
  is_legacy_format: () => is_legacy_format,
  is_missing_value: () => is_missing_value,
  is_missing_value_object: () => is_missing_value_object,
  listStataCharacteristics: () => listStataCharacteristics,
  listStataNotes: () => listStataNotes,
  make_missing_value: () => make_missing_value,
  missing_type_to_label_key: () => missing_type_to_label_key,
  renumberStataNotes: () => renumberStataNotes,
  setStataCharacteristic: () => setStataCharacteristic,
  setStataNote: () => setStataNote
});
module.exports = __toCommonJS(node_exports);
var fs = __toESM(require("fs"), 1);

// src/types.ts
var FORMAT_SIGNATURES = {
  117: "<stata_dta><header><release>117</release>",
  118: "<stata_dta><header><release>118</release>",
  119: "<stata_dta><header><release>119</release>"
};
var LEGACY_FORMAT_SET = /* @__PURE__ */ new Set([105, 108, 110, 111, 113, 114, 115]);
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
var PRE111_TYPE_CODES = {
  98: { type: "byte", width: 1 },
  105: { type: "int", width: 2 },
  108: { type: "long", width: 4 },
  102: { type: "float", width: 4 },
  100: { type: "double", width: 8 }
};
var MAX_STR_WIDTH_LEGACY = 244;
function byte_width_for_legacy_type_code(code, format_version) {
  if (format_version < 111) {
    const my_entry = PRE111_TYPE_CODES[code];
    if (my_entry) return my_entry.width;
    if (code >= 128 && code <= 255) return code - 127;
  } else {
    const my_entry = LEGACY_TYPE_CODES[code];
    if (my_entry) return my_entry.width;
    if (code >= 1 && code <= MAX_STR_WIDTH_LEGACY) return code;
  }
  throw new Error(
    `Unknown legacy type code ${code}`
  );
}
function legacy_type_code_to_dta_type(code, format_version) {
  if (format_version < 111) {
    const my_entry = PRE111_TYPE_CODES[code];
    if (my_entry) return my_entry.type;
    if (code >= 128 && code <= 255) {
      return `str${code - 127}`;
    }
  } else {
    const my_entry = LEGACY_TYPE_CODES[code];
    if (my_entry) return my_entry.type;
    if (code >= 1 && code <= MAX_STR_WIDTH_LEGACY) {
      return `str${code}`;
    }
  }
  throw new Error(
    `Unknown legacy type code ${code}`
  );
}

// src/text-encoding.ts
function decode_text_range(decoder, bytes, start, end) {
  if (start < 0 || end > bytes.length) {
    return decoder.decode(bytes.subarray(start, end));
  }
  const my_length = end - start;
  if (my_length > 12) {
    return decoder.decode(bytes.subarray(start, end));
  }
  for (let i = start; i < end; i++) {
    if (bytes[i] >= 128) {
      return decoder.decode(bytes.subarray(start, end));
    }
  }
  switch (my_length) {
    case 0:
      return "";
    case 1:
      return String.fromCharCode(bytes[start]);
    case 2:
      return String.fromCharCode(bytes[start], bytes[start + 1]);
    case 3:
      return String.fromCharCode(
        bytes[start],
        bytes[start + 1],
        bytes[start + 2]
      );
    case 4:
      return String.fromCharCode(
        bytes[start],
        bytes[start + 1],
        bytes[start + 2],
        bytes[start + 3]
      );
    case 5:
      return String.fromCharCode(
        bytes[start],
        bytes[start + 1],
        bytes[start + 2],
        bytes[start + 3],
        bytes[start + 4]
      );
    case 6:
      return String.fromCharCode(
        bytes[start],
        bytes[start + 1],
        bytes[start + 2],
        bytes[start + 3],
        bytes[start + 4],
        bytes[start + 5]
      );
    case 7:
      return String.fromCharCode(
        bytes[start],
        bytes[start + 1],
        bytes[start + 2],
        bytes[start + 3],
        bytes[start + 4],
        bytes[start + 5],
        bytes[start + 6]
      );
    case 8:
      return String.fromCharCode(
        bytes[start],
        bytes[start + 1],
        bytes[start + 2],
        bytes[start + 3],
        bytes[start + 4],
        bytes[start + 5],
        bytes[start + 6],
        bytes[start + 7]
      );
    case 9:
      return String.fromCharCode(
        bytes[start],
        bytes[start + 1],
        bytes[start + 2],
        bytes[start + 3],
        bytes[start + 4],
        bytes[start + 5],
        bytes[start + 6],
        bytes[start + 7],
        bytes[start + 8]
      );
    case 10:
      return String.fromCharCode(
        bytes[start],
        bytes[start + 1],
        bytes[start + 2],
        bytes[start + 3],
        bytes[start + 4],
        bytes[start + 5],
        bytes[start + 6],
        bytes[start + 7],
        bytes[start + 8],
        bytes[start + 9]
      );
    case 11:
      return String.fromCharCode(
        bytes[start],
        bytes[start + 1],
        bytes[start + 2],
        bytes[start + 3],
        bytes[start + 4],
        bytes[start + 5],
        bytes[start + 6],
        bytes[start + 7],
        bytes[start + 8],
        bytes[start + 9],
        bytes[start + 10]
      );
    case 12:
      return String.fromCharCode(
        bytes[start],
        bytes[start + 1],
        bytes[start + 2],
        bytes[start + 3],
        bytes[start + 4],
        bytes[start + 5],
        bytes[start + 6],
        bytes[start + 7],
        bytes[start + 8],
        bytes[start + 9],
        bytes[start + 10],
        bytes[start + 11]
      );
    default:
      return decoder.decode(bytes.subarray(start, end));
  }
}
var UTF8_DECODER = new TextDecoder(
  "utf-8",
  { ignoreBOM: true }
);
var WINDOWS_1252_DECODER = new TextDecoder(
  "windows-1252",
  { ignoreBOM: true }
);
var ISO_8859_1_DECODER = {
  decode(input) {
    const my_chunk_size = 8192;
    let my_result = "";
    for (let i = 0; i < input.length; i += my_chunk_size) {
      my_result += String.fromCharCode(
        ...input.subarray(i, i + my_chunk_size)
      );
    }
    return my_result;
  }
};
function normalize_text_encoding(encoding = "auto") {
  if (typeof encoding !== "string") {
    throw new Error(
      `Unsupported text encoding ${JSON.stringify(encoding)}; use auto, utf-8, windows-1252, or iso-8859-1`
    );
  }
  const my_key = encoding.toLowerCase().replaceAll(/[-_ ]/g, "");
  switch (my_key) {
    case "auto":
      return "auto";
    case "utf8":
      return "utf-8";
    case "windows1252":
    case "cp1252":
      return "windows-1252";
    case "iso88591":
    case "latin1":
      return "iso-8859-1";
  }
  throw new Error(
    `Unsupported text encoding ${JSON.stringify(encoding)}; use auto, utf-8, windows-1252, or iso-8859-1`
  );
}
function validate_text_encoding(encoding = "auto") {
  normalize_text_encoding(encoding);
}
function resolve_text_encoding(format_version, encoding = "auto") {
  const my_encoding = normalize_text_encoding(encoding);
  if (my_encoding === "auto") {
    return format_version >= 118 ? "utf-8" : "windows-1252";
  }
  return my_encoding;
}
function text_decoder(encoding) {
  switch (encoding) {
    case "utf-8":
      return UTF8_DECODER;
    case "windows-1252":
      return WINDOWS_1252_DECODER;
    case "iso-8859-1":
      return ISO_8859_1_DECODER;
  }
}

// src/stata-metadata.ts
var NOTE_NAME = /^note([0-9]+)$/;
var MAX_STATA_METADATA_VALUE_BYTES = 67784;
var TEXT_ENCODER = new TextEncoder();
function noteNumber(name) {
  const match = NOTE_NAME.exec(name);
  if (match === null) return null;
  const number = Number(match[1]);
  return Number.isInteger(number) && number >= 1 && number <= 9999 ? number : null;
}
function reservedCharacteristicName(name) {
  return NOTE_NAME.test(name) || name === "_lang_list" || name === "_lang_c" || name.startsWith("_lang_v_") || name.startsWith("_lang_l_");
}
function validCharacteristicNameShape(name) {
  return /^[_\p{L}][_\p{L}\p{N}]*$/u.test(name) && codePointLengthAtMost(name, 32) && utf8LengthAtMost(name, 128);
}
var StataMetadataCollector = class {
  dataset;
  variables;
  targetIndexes;
  indexes = /* @__PURE__ */ new Map();
  constructor(dataset, variables) {
    this.dataset = dataset;
    this.variables = variables;
  }
  targetIndex(target) {
    if (target === "_dta") return 0;
    if (this.targetIndexes === void 0) {
      this.targetIndexes = /* @__PURE__ */ new Map();
      this.variables.forEach((variable, index) => {
        this.targetIndexes.set(variable.name, index + 1);
      });
    }
    return this.targetIndexes.get(target);
  }
  scope(scopeIndex) {
    return scopeIndex === 0 ? this.dataset : this.variables[scopeIndex - 1];
  }
  scopeIndexes(scopeIndex) {
    const existing = this.indexes.get(scopeIndex);
    if (existing !== void 0) return existing;
    const scope = this.scope(scopeIndex);
    const indexes = {
      notes: new Map(
        scope.notes.map((note, index) => [note.number, index])
      ),
      characteristics: new Map(
        scope.characteristics.map((item, index) => [item.name, index])
      )
    };
    this.indexes.set(scopeIndex, indexes);
    return indexes;
  }
  classify(target, name) {
    if (!validCharacteristicNameShape(name)) {
      throw new Error("Invalid on-disk Stata characteristic name");
    }
    const number = noteNumber(name);
    if (number === null && reservedCharacteristicName(name)) return null;
    const scopeIndex = this.targetIndex(target);
    if (scopeIndex === void 0) return null;
    return { scopeIndex, name, noteNumber: number };
  }
  push(record) {
    this.pushLazy(record.target, record.name, () => record.value);
  }
  pushLazy(target, name, value) {
    const accepted = this.classify(target, name);
    if (accepted === null) return false;
    this.pushAccepted(accepted, value());
    return true;
  }
  pushAccepted(accepted, value) {
    const scope = this.scope(accepted.scopeIndex);
    const indexes = this.scopeIndexes(accepted.scopeIndex);
    if (accepted.noteNumber !== null) {
      const existing2 = indexes.notes.get(accepted.noteNumber);
      if (existing2 === void 0) {
        indexes.notes.set(accepted.noteNumber, scope.notes.length);
        scope.notes.push({ number: accepted.noteNumber, text: value });
      } else {
        scope.notes[existing2].text = value;
      }
      return;
    }
    const existing = indexes.characteristics.get(accepted.name);
    if (existing === void 0) {
      indexes.characteristics.set(accepted.name, scope.characteristics.length);
      scope.characteristics.push({ name: accepted.name, value });
    } else {
      scope.characteristics[existing].value = value;
    }
  }
  finish() {
    for (const scopeIndex of this.indexes.keys()) {
      this.scope(scopeIndex).notes.sort(
        (left, right) => left.number - right.number
      );
    }
  }
};
function validNoteNumber(number) {
  if (!Number.isInteger(number) || number < 1 || number > 9999) {
    throw new Error("A note number must be an integer from 1 through 9999");
  }
}
function codePointLengthAtMost(value, limit) {
  let count = 0;
  for (const _character of value) {
    count++;
    if (count > limit) return false;
  }
  return true;
}
function utf8LengthAtMost(value, limit) {
  const output = new Uint8Array(Math.min(limit + 1, value.length * 3));
  const encoded = TEXT_ENCODER.encodeInto(value, output);
  return encoded.read === value.length && encoded.written <= limit;
}
function validCharacteristicName(name) {
  if (!validCharacteristicNameShape(name) || reservedCharacteristicName(name)) {
    throw new Error("Invalid or reserved Stata characteristic name");
  }
}
function stataMetadataValueEnd(bytes, start, length) {
  if (length > MAX_STATA_METADATA_VALUE_BYTES + 1) {
    throw new Error("Characteristic value exceeds the 67,784-byte limit");
  }
  const limit = start + length;
  let end = start;
  while (end < limit && bytes[end] !== 0) end++;
  if (end - start > MAX_STATA_METADATA_VALUE_BYTES) {
    throw new Error("Characteristic value exceeds the 67,784-byte limit");
  }
  return end;
}
function validMetadataValue(value) {
  if (typeof value !== "string" || value.includes("\0") || !utf8LengthAtMost(value, MAX_STATA_METADATA_VALUE_BYTES)) {
    throw new Error("Invalid or over-limit Stata metadata value");
  }
}
function listStataNotes(target) {
  return target.notes.map((note) => ({ ...note }));
}
function getStataNote(target, number) {
  validNoteNumber(number);
  return target.notes.find((note) => note.number === number)?.text;
}
function setStataNote(target, number, text) {
  validNoteNumber(number);
  validMetadataValue(text);
  const existing = target.notes.find((note) => note.number === number);
  if (existing === void 0) target.notes.push({ number, text });
  else existing.text = text;
  target.notes.sort((left, right) => left.number - right.number);
}
function addStataNote(target, text) {
  const number = target.notes.length === 0 ? 1 : Math.max(...target.notes.map((note) => note.number)) + 1;
  validNoteNumber(number);
  setStataNote(target, number, text);
  return number;
}
function dropStataNotes(target, numbers) {
  if (numbers === void 0) {
    target.notes = [];
    return;
  }
  numbers.forEach(validNoteNumber);
  const dropped = new Set(numbers);
  target.notes = target.notes.filter((note) => !dropped.has(note.number));
}
function renumberStataNotes(target, start = 1) {
  validNoteNumber(start);
  if (target.notes.length > 0 && start + target.notes.length - 1 > 9999) {
    throw new Error("Renumbered notes would exceed note number 9999");
  }
  target.notes.sort((left, right) => left.number - right.number).forEach((note, index) => {
    note.number = start + index;
  });
}
function listStataCharacteristics(target) {
  return target.characteristics.map((characteristic) => ({ ...characteristic }));
}
function getStataCharacteristic(target, name) {
  validCharacteristicName(name);
  return target.characteristics.find((item) => item.name === name)?.value;
}
function setStataCharacteristic(target, name, value) {
  validCharacteristicName(name);
  validMetadataValue(value);
  const existing = target.characteristics.find((item) => item.name === name);
  if (existing === void 0) target.characteristics.push({ name, value });
  else existing.value = value;
}
function dropStataCharacteristics(target, names) {
  if (names === void 0) {
    target.characteristics = [];
    return;
  }
  names.forEach(validCharacteristicName);
  const dropped = new Set(names);
  target.characteristics = target.characteristics.filter(
    (characteristic) => !dropped.has(characteristic.name)
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
var ASCII_DECODER = new TextDecoder("utf-8");
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
var TAG_CHARACTERISTICS_OPEN = encode_tag("<characteristics>");
var TAG_CHARACTERISTICS_CLOSE = encode_tag("</characteristics>");
var TAG_CHARACTERISTIC_OPEN = encode_tag("<ch>");
var TAG_CHARACTERISTIC_CLOSE = encode_tag("</ch>");
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
function read_fixed_string(bytes, offset, field_width, decoder) {
  let my_end = offset;
  const my_limit = offset + field_width;
  while (my_end < my_limit && bytes[my_end] !== 0) {
    my_end++;
  }
  return decoder.decode(
    bytes.subarray(offset, my_end)
  );
}
function tag_at(bytes, offset, tag) {
  if (offset < 0 || offset + tag.length > bytes.length) return false;
  for (let i = 0; i < tag.length; i++) {
    if (bytes[offset + i] !== tag[i]) return false;
  }
  return true;
}
function parse_characteristics(bytes, view, little_endian, section_offsets, field_width, decoder, dataset, variables) {
  let pos = section_offsets.characteristics;
  if (!tag_at(bytes, pos, TAG_CHARACTERISTICS_OPEN)) {
    throw new Error("Missing <characteristics> tag");
  }
  pos += TAG_CHARACTERISTICS_OPEN.length;
  const names_length = field_width * 2;
  const collector = new StataMetadataCollector(dataset, variables);
  while (pos < section_offsets.data) {
    if (tag_at(bytes, pos, TAG_CHARACTERISTICS_CLOSE)) {
      pos += TAG_CHARACTERISTICS_CLOSE.length;
      if (pos !== section_offsets.data) {
        throw new Error("Characteristics section does not end at the mapped data offset");
      }
      collector.finish();
      return;
    }
    if (!tag_at(bytes, pos, TAG_CHARACTERISTIC_OPEN)) {
      throw new Error("Invalid characteristic record tag");
    }
    pos += TAG_CHARACTERISTIC_OPEN.length;
    if (pos + 4 > section_offsets.data) {
      throw new Error("Truncated characteristic length");
    }
    const length = view.getUint32(pos, little_endian);
    pos += 4;
    if (length < names_length || pos + length + TAG_CHARACTERISTIC_CLOSE.length > section_offsets.data) {
      throw new Error("Truncated characteristic payload");
    }
    const target = read_fixed_string(bytes, pos, field_width, decoder);
    const name = read_fixed_string(
      bytes,
      pos + field_width,
      field_width,
      decoder
    );
    const valueLength = length - names_length;
    const valueStart = pos + names_length;
    const valueEnd = stataMetadataValueEnd(bytes, valueStart, valueLength);
    collector.pushLazy(target, name, () => {
      return decoder.decode(bytes.subarray(valueStart, valueEnd));
    });
    pos += length;
    if (!tag_at(bytes, pos, TAG_CHARACTERISTIC_CLOSE)) {
      throw new Error("Missing </ch> tag");
    }
    pos += TAG_CHARACTERISTIC_CLOSE.length;
  }
  throw new Error("Missing </characteristics> tag");
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
  const my_str = ASCII_DECODER.decode(
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
function parse_dataset_label(bytes, view, little_endian, format_version, start, decoder) {
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
  const my_label = decoder.decode(
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
    const my_big_val = view.getBigUint64(
      my_data_start + i * 8,
      little_endian
    );
    if (my_big_val > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new Error("Section offset exceeds JavaScript safe integer limit");
    }
    my_offsets[SECTION_OFFSET_KEYS[i]] = Number(my_big_val);
  }
  return my_offsets;
}
function parse_modern_metadata_header(buffer, options = {}) {
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  const format_version = detect_format_version(bytes);
  const text_encoding = resolve_text_encoding(format_version, options.encoding);
  const decoder = text_decoder(text_encoding);
  const widths = FIELD_WIDTHS[format_version];
  const { byte_order, end: after_byteorder } = parse_byte_order(bytes, 0);
  const little_endian = byte_order === "LSF";
  const { nvar, end: after_k } = parse_nvar(
    bytes,
    view,
    little_endian,
    format_version,
    after_byteorder
  );
  const { nobs, end: after_n } = parse_nobs(
    bytes,
    view,
    little_endian,
    format_version,
    after_k
  );
  const { dataset_label, end: after_label } = parse_dataset_label(
    bytes,
    view,
    little_endian,
    format_version,
    after_n,
    decoder
  );
  const timestamp_close = find_bytes(bytes, TAG_TIMESTAMP_CLOSE, after_label);
  if (timestamp_close === -1) throw new Error("Missing </timestamp> tag");
  const section_offsets = parse_section_map(
    bytes,
    view,
    little_endian,
    timestamp_close
  );
  return {
    format_version,
    text_encoding,
    decoder,
    widths,
    byte_order,
    little_endian,
    nvar,
    nobs,
    dataset_label,
    section_offsets
  };
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
function parse_fixed_string_section(bytes, tag, search_start, nvar, field_width, decoder) {
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
        field_width,
        decoder
      )
    );
  }
  return the_strings;
}
function parse_metadata_from_header(buffer, header) {
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  const {
    format_version,
    text_encoding,
    decoder: my_decoder,
    widths: my_widths,
    byte_order,
    little_endian,
    nvar,
    nobs,
    dataset_label,
    section_offsets
  } = header;
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
    my_widths.varname,
    my_decoder
  );
  const the_formats = parse_fixed_string_section(
    bytes,
    TAG_FORMATS_OPEN,
    section_offsets.formats,
    nvar,
    my_widths.format,
    my_decoder
  );
  const the_value_label_names = parse_fixed_string_section(
    bytes,
    TAG_VALUE_LABEL_NAMES_OPEN,
    section_offsets.value_label_names,
    nvar,
    my_widths.value_label_name,
    my_decoder
  );
  const the_variable_labels = parse_fixed_string_section(
    bytes,
    TAG_VARIABLE_LABELS_OPEN,
    section_offsets.variable_labels,
    nvar,
    my_widths.variable_label,
    my_decoder
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
      notes: [],
      characteristics: [],
      byte_width: my_width,
      byte_offset: my_running_offset
    });
    my_running_offset += my_width;
  }
  const notes = [];
  const characteristics = [];
  parse_characteristics(
    bytes,
    view,
    little_endian,
    section_offsets,
    my_widths.varname,
    my_decoder,
    { notes, characteristics },
    the_variables
  );
  return {
    format_version,
    text_encoding,
    byte_order,
    nvar,
    nobs,
    dataset_label,
    notes,
    characteristics,
    variables: the_variables,
    section_offsets,
    obs_length: my_running_offset
  };
}

// src/legacy-layout.ts
var LAYOUTS = {
  105: {
    header_size: 60,
    dataset_label_width: 32,
    varname_width: 9,
    format_width: 12,
    value_label_name_width: 9,
    variable_label_width: 32,
    expansion_length_width: 2,
    value_label_table_name_width: 9,
    value_label_layout: "fixed8"
  },
  108: {
    header_size: 109,
    dataset_label_width: 81,
    varname_width: 9,
    format_width: 12,
    value_label_name_width: 9,
    variable_label_width: 81,
    expansion_length_width: 2,
    value_label_table_name_width: 9,
    value_label_layout: "offset_table"
  },
  110: {
    header_size: 109,
    dataset_label_width: 81,
    varname_width: 33,
    format_width: 12,
    value_label_name_width: 33,
    variable_label_width: 81,
    expansion_length_width: 4,
    value_label_table_name_width: 33,
    value_label_layout: "offset_table"
  },
  111: {
    header_size: 109,
    dataset_label_width: 81,
    varname_width: 33,
    format_width: 12,
    value_label_name_width: 33,
    variable_label_width: 81,
    expansion_length_width: 4,
    value_label_table_name_width: 33,
    value_label_layout: "offset_table"
  },
  113: {
    header_size: 109,
    dataset_label_width: 81,
    varname_width: 33,
    format_width: 12,
    value_label_name_width: 33,
    variable_label_width: 81,
    expansion_length_width: 4,
    value_label_table_name_width: 33,
    value_label_layout: "offset_table"
  },
  114: {
    header_size: 109,
    dataset_label_width: 81,
    varname_width: 33,
    format_width: 49,
    value_label_name_width: 33,
    variable_label_width: 81,
    expansion_length_width: 4,
    value_label_table_name_width: 33,
    value_label_layout: "offset_table"
  },
  115: {
    header_size: 109,
    dataset_label_width: 81,
    varname_width: 33,
    format_width: 49,
    value_label_name_width: 33,
    variable_label_width: 81,
    expansion_length_width: 4,
    value_label_table_name_width: 33,
    value_label_layout: "offset_table"
  }
};
function legacy_layout_for_version(version) {
  return LAYOUTS[version];
}
function legacy_expansion_header_size(layout) {
  return 1 + layout.expansion_length_width;
}

// src/legacy-header.ts
var SORTLIST_ENTRY_WIDTH = 2;
function read_fixed_string2(bytes, offset, field_width, decoder) {
  let my_end = offset;
  const my_limit = offset + field_width;
  while (my_end < my_limit && bytes[my_end] !== 0) {
    my_end++;
  }
  return decoder.decode(
    bytes.subarray(offset, my_end)
  );
}
function legacy_metadata_fixed_size(nvar, format_version) {
  const layout = legacy_layout_for_version(format_version);
  const my_sections_size = nvar + nvar * layout.varname_width + (nvar + 1) * SORTLIST_ENTRY_WIDTH + nvar * layout.format_width + nvar * layout.value_label_name_width + nvar * layout.variable_label_width;
  return layout.header_size + my_sections_size;
}
function scan_expansion_fields(view, little_endian, start, buffer_length, format_version, decoder, dataset, variables) {
  let pos = start;
  const bytes = bytes_from_view(view);
  const layout = legacy_layout_for_version(format_version);
  const my_header_size = legacy_expansion_header_size(layout);
  const collector = new StataMetadataCollector(dataset, variables);
  while (pos + my_header_size <= buffer_length) {
    const my_data_type = view.getUint8(pos);
    const my_len = layout.expansion_length_width === 2 ? view.getInt16(pos + 1, little_endian) : view.getInt32(pos + 1, little_endian);
    pos += my_header_size;
    if (my_data_type === 0 && my_len === 0) {
      collector.finish();
      return pos;
    }
    if (my_data_type === 0 || my_len < 0) {
      throw new Error("Invalid legacy expansion field");
    }
    if (pos + my_len > buffer_length) {
      throw new Error("Truncated legacy expansion field");
    }
    if (my_data_type === 1 && my_len >= 2 * layout.varname_width) {
      const my_variable = read_fixed_string2(
        bytes,
        pos,
        layout.varname_width,
        decoder
      );
      const my_characteristic = read_fixed_string2(
        bytes,
        pos + layout.varname_width,
        layout.varname_width,
        decoder
      );
      const my_value_length = my_len - 2 * layout.varname_width;
      const valueStart = pos + 2 * layout.varname_width;
      const valueEnd = stataMetadataValueEnd(
        bytes,
        valueStart,
        my_value_length
      );
      collector.pushLazy(
        my_variable,
        my_characteristic,
        () => decoder.decode(bytes.subarray(valueStart, valueEnd))
      );
    }
    pos += my_len;
  }
  throw new Error("Missing legacy expansion-field terminator");
}
function bytes_from_view(view) {
  return new Uint8Array(view.buffer, view.byteOffset, view.byteLength);
}
function parse_legacy_metadata(buffer, file_size, options = {}) {
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  const my_version_byte = bytes[0];
  if (my_version_byte !== 105 && my_version_byte !== 108 && my_version_byte !== 110 && my_version_byte !== 111 && my_version_byte !== 113 && my_version_byte !== 114 && my_version_byte !== 115) {
    throw new Error(
      `Not a legacy .dta file: version byte ${my_version_byte}`
    );
  }
  const format_version = my_version_byte;
  const text_encoding = resolve_text_encoding(
    format_version,
    options.encoding
  );
  const my_decoder = text_decoder(text_encoding);
  const layout = legacy_layout_for_version(format_version);
  const my_byte_order_code = bytes[1];
  if (my_byte_order_code !== 1 && my_byte_order_code !== 2) {
    throw new Error(
      `Invalid byte order code: ${my_byte_order_code}`
    );
  }
  const byte_order = my_byte_order_code === 1 ? "MSF" : "LSF";
  const little_endian = byte_order === "LSF";
  if (bytes[2] !== 1) {
    throw new Error(`Invalid legacy file type: ${bytes[2]}`);
  }
  const nvar = view.getUint16(4, little_endian);
  const nobs = view.getInt32(6, little_endian);
  if (nobs < 0) {
    throw new Error(
      `Invalid observation count: ${nobs}`
    );
  }
  const dataset_label = read_fixed_string2(
    bytes,
    10,
    layout.dataset_label_width,
    my_decoder
  );
  const my_fmt_width = layout.format_width;
  let pos = layout.header_size;
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
        pos + i * layout.varname_width,
        layout.varname_width,
        my_decoder
      )
    );
  }
  pos += nvar * layout.varname_width;
  const my_sortlist_offset = pos;
  pos += (nvar + 1) * SORTLIST_ENTRY_WIDTH;
  const my_formats_offset = pos;
  const the_formats = [];
  for (let i = 0; i < nvar; i++) {
    the_formats.push(
      read_fixed_string2(
        bytes,
        pos + i * my_fmt_width,
        my_fmt_width,
        my_decoder
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
        pos + i * layout.value_label_name_width,
        layout.value_label_name_width,
        my_decoder
      )
    );
  }
  pos += nvar * layout.value_label_name_width;
  const my_variable_labels_offset = pos;
  const the_variable_labels = [];
  for (let i = 0; i < nvar; i++) {
    the_variable_labels.push(
      read_fixed_string2(
        bytes,
        pos + i * layout.variable_label_width,
        layout.variable_label_width,
        my_decoder
      )
    );
  }
  pos += nvar * layout.variable_label_width;
  let my_running_offset = 0;
  const the_variables = [];
  for (let i = 0; i < nvar; i++) {
    const my_code = the_type_codes[i];
    const my_width = byte_width_for_legacy_type_code(my_code, format_version);
    the_variables.push({
      name: the_varnames[i],
      type: legacy_type_code_to_dta_type(my_code, format_version),
      type_code: my_code,
      format: the_formats[i],
      label: the_variable_labels[i],
      value_label_name: the_value_label_names[i],
      notes: [],
      characteristics: [],
      byte_width: my_width,
      byte_offset: my_running_offset
    });
    my_running_offset += my_width;
  }
  const obs_length = my_running_offset;
  const notes = [];
  const characteristics = [];
  const my_expansion_offset = pos;
  const my_data_offset = scan_expansion_fields(
    view,
    little_endian,
    pos,
    buffer.byteLength,
    format_version,
    my_decoder,
    { notes, characteristics },
    the_variables
  );
  const my_value_labels_offset = Number(
    BigInt(my_data_offset) + BigInt(nobs) * BigInt(obs_length)
  );
  if (!Number.isSafeInteger(my_value_labels_offset) || my_value_labels_offset > file_size) {
    throw new Error("Truncated legacy observation data");
  }
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
    text_encoding,
    byte_order,
    nvar,
    nobs,
    dataset_label,
    notes,
    characteristics,
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
var MISSING_TYPES = Array.from(
  { length: 27 },
  (_, offset) => offset === 0 ? "." : `.${String.fromCharCode(96 + offset)}`
);
function classify_missing_from_offset(offset) {
  return MISSING_TYPES[offset] ?? null;
}
function integer_missing_offset(value, dot, z, modern) {
  if (!modern) return value === z ? 0 : -1;
  return value >= dot && value <= z ? value - dot : -1;
}
function byte_missing_offset(value, modern) {
  return integer_missing_offset(
    value,
    BYTE_MISSING_DOT,
    BYTE_MISSING_Z,
    modern
  );
}
function int_missing_offset(value, modern) {
  return integer_missing_offset(
    value,
    INT_MISSING_DOT,
    INT_MISSING_Z,
    modern
  );
}
function long_missing_offset(value, modern) {
  return integer_missing_offset(
    value,
    LONG_MISSING_DOT,
    LONG_MISSING_Z,
    modern
  );
}
function float_missing_offset(raw_value, modern) {
  if (!modern) {
    return raw_value >= FLOAT_MISSING_DOT_RAW && raw_value < 2147483648 ? 0 : -1;
  }
  if (raw_value < FLOAT_MISSING_DOT_RAW || raw_value > FLOAT_MISSING_Z_RAW) {
    return -1;
  }
  const my_delta = raw_value - FLOAT_MISSING_DOT_RAW;
  return my_delta % FLOAT_MISSING_STEP_RAW === 0 ? my_delta / FLOAT_MISSING_STEP_RAW : -1;
}
function classify_float_raw_missing(raw_value) {
  return classify_missing_from_offset(
    float_missing_offset(raw_value, true)
  );
}
function double_missing_offset_from_parts(hi_word, lo_word) {
  if (hi_word >>> 16 !== DOUBLE_PREFIX_HI) {
    return -1;
  }
  const my_letter = hi_word >>> 8 & 255;
  if (my_letter > DOUBLE_LETTER_MAX || (hi_word & 255) !== 0 || lo_word !== 0) {
    return -1;
  }
  return my_letter;
}
function classify_double_big_endian_parts(hi_word, lo_word) {
  return classify_missing_from_offset(
    double_missing_offset_from_parts(hi_word, lo_word)
  );
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
function missing_value_from_offset(offset) {
  return make_missing_value(MISSING_TYPES[offset]);
}
function is_missing_value_object(value) {
  return typeof value === "object" && value !== null && value.kind === "missing" && typeof value.missing_type === "string";
}
function classify_raw_float_missing(raw_value) {
  return classify_float_raw_missing(raw_value);
}
function double_missing_offset_for_version(view, offset, little_endian, format_version) {
  const my_hi_word = little_endian ? view.getUint32(offset + 4, true) : view.getUint32(offset, false);
  const my_lo_word = little_endian ? view.getUint32(offset, true) : view.getUint32(offset + 4, false);
  if (format_version >= 113) {
    return double_missing_offset_from_parts(
      my_hi_word,
      my_lo_word
    );
  }
  if (my_hi_word >= 2145386496 && my_hi_word < 2147483648) {
    return 0;
  }
  return format_version === 105 && my_hi_word === 1421869056 && my_lo_word === 0 ? 0 : -1;
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
      return classify_missing_from_offset(
        byte_missing_offset(value, true)
      );
    case "int":
      return classify_missing_from_offset(
        int_missing_offset(value, true)
      );
    case "long":
      return classify_missing_from_offset(
        long_missing_offset(value, true)
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
var DATA_TAG_LENGTH = "<data>".length;
var STRL_PLACEHOLDER = "__strl__";
function assert_valid_row_range(start, count) {
  const my_start_valid = Number.isInteger(start) || start === Infinity || start === -Infinity;
  const my_count_valid = Number.isInteger(count) || count === Infinity || count === -Infinity;
  if (!my_start_valid || !my_count_valid) {
    throw new RangeError(
      "Row start and count must not be NaN or fractional"
    );
  }
}
function data_buffer_view(buffer) {
  return buffer instanceof Uint8Array ? new DataView(
    buffer.buffer,
    buffer.byteOffset,
    buffer.byteLength
  ) : new DataView(buffer);
}
function buffer_views(buffer) {
  return {
    view: data_buffer_view(buffer),
    bytes: buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer)
  };
}
function decoder_for_metadata(metadata) {
  switch (metadata.text_encoding) {
    case "utf-8":
    case "windows-1252":
    case "iso-8859-1":
      return text_decoder(metadata.text_encoding);
    default:
      return text_decoder(resolve_text_encoding(
        metadata.format_version,
        metadata.text_encoding
      ));
  }
}
function read_fixed_string3(bytes, offset, width, decoder) {
  if (width === 0 || bytes[offset] === 0) return "";
  let my_end = offset + 1;
  const my_limit = offset + width;
  while (my_end < my_limit && bytes[my_end] !== 0) {
    my_end++;
  }
  return decode_text_range(decoder, bytes, offset, my_end);
}
function read_cell(view, bytes, offset, variable, little_endian, modern_missing, decoder, format_version) {
  let my_missing = -1;
  switch (variable.type) {
    case "byte": {
      const my_value = view.getInt8(offset);
      my_missing = byte_missing_offset(
        my_value,
        modern_missing
      );
      return my_missing >= 0 ? missing_value_from_offset(my_missing) : my_value;
    }
    case "int": {
      const my_value = view.getInt16(
        offset,
        little_endian
      );
      my_missing = int_missing_offset(
        my_value,
        modern_missing
      );
      return my_missing >= 0 ? missing_value_from_offset(my_missing) : my_value;
    }
    case "long": {
      const my_value = view.getInt32(
        offset,
        little_endian
      );
      my_missing = long_missing_offset(
        my_value,
        modern_missing
      );
      return my_missing >= 0 ? missing_value_from_offset(my_missing) : my_value;
    }
    case "float": {
      const my_raw = view.getUint32(
        offset,
        little_endian
      );
      my_missing = float_missing_offset(
        my_raw,
        modern_missing
      );
      return my_missing >= 0 ? missing_value_from_offset(my_missing) : view.getFloat32(offset, little_endian);
    }
    case "double":
      my_missing = double_missing_offset_for_version(
        view,
        offset,
        little_endian,
        format_version
      );
      return my_missing >= 0 ? missing_value_from_offset(my_missing) : view.getFloat64(offset, little_endian);
    case "strL":
      return STRL_PLACEHOLDER;
    default:
      return read_fixed_string3(
        bytes,
        offset,
        variable.byte_width,
        decoder
      );
  }
}
function decode_column_into_values(view, bytes, values, output_start, count, variable, row_width, little_endian, modern_missing, decoder, format_version, write_strl_placeholder) {
  let my_offset = variable.byte_offset;
  const my_end = output_start + count;
  switch (variable.type) {
    case "byte":
      for (let i = output_start; i < my_end; i++, my_offset += row_width) {
        const my_value = view.getInt8(my_offset);
        const my_missing = byte_missing_offset(
          my_value,
          modern_missing
        );
        values[i] = my_missing >= 0 ? missing_value_from_offset(my_missing) : my_value;
      }
      return;
    case "int":
      for (let i = output_start; i < my_end; i++, my_offset += row_width) {
        const my_value = view.getInt16(my_offset, little_endian);
        const my_missing = int_missing_offset(
          my_value,
          modern_missing
        );
        values[i] = my_missing >= 0 ? missing_value_from_offset(my_missing) : my_value;
      }
      return;
    case "long":
      for (let i = output_start; i < my_end; i++, my_offset += row_width) {
        const my_value = view.getInt32(my_offset, little_endian);
        const my_missing = long_missing_offset(
          my_value,
          modern_missing
        );
        values[i] = my_missing >= 0 ? missing_value_from_offset(my_missing) : my_value;
      }
      return;
    case "float":
      for (let i = output_start; i < my_end; i++, my_offset += row_width) {
        const my_raw = view.getUint32(my_offset, little_endian);
        const my_missing = float_missing_offset(
          my_raw,
          modern_missing
        );
        values[i] = my_missing >= 0 ? missing_value_from_offset(my_missing) : view.getFloat32(my_offset, little_endian);
      }
      return;
    case "double":
      for (let i = output_start; i < my_end; i++, my_offset += row_width) {
        const my_missing = double_missing_offset_for_version(
          view,
          my_offset,
          little_endian,
          format_version
        );
        values[i] = my_missing >= 0 ? missing_value_from_offset(my_missing) : view.getFloat64(my_offset, little_endian);
      }
      return;
    case "strL":
      if (write_strl_placeholder) {
        for (let i = output_start; i < my_end; i++) {
          values[i] = STRL_PLACEHOLDER;
        }
      }
      return;
    default:
      for (let i = output_start; i < my_end; i++, my_offset += row_width) {
        values[i] = read_fixed_string3(
          bytes,
          my_offset,
          variable.byte_width,
          decoder
        );
      }
  }
}
function decode_single_column_into_rows(view, bytes, rows, output_start, count, row_base_offset, variable, row_width, little_endian, modern_missing, decoder, format_version) {
  let my_offset = row_base_offset + variable.byte_offset;
  const my_end = output_start + count;
  switch (variable.type) {
    case "byte":
      for (let i = output_start; i < my_end; i++, my_offset += row_width) {
        const my_value = view.getInt8(my_offset);
        const my_missing = byte_missing_offset(
          my_value,
          modern_missing
        );
        rows[i] = [my_missing >= 0 ? missing_value_from_offset(my_missing) : my_value];
      }
      return;
    case "int":
      for (let i = output_start; i < my_end; i++, my_offset += row_width) {
        const my_value = view.getInt16(my_offset, little_endian);
        const my_missing = int_missing_offset(
          my_value,
          modern_missing
        );
        rows[i] = [my_missing >= 0 ? missing_value_from_offset(my_missing) : my_value];
      }
      return;
    case "long":
      for (let i = output_start; i < my_end; i++, my_offset += row_width) {
        const my_value = view.getInt32(my_offset, little_endian);
        const my_missing = long_missing_offset(
          my_value,
          modern_missing
        );
        rows[i] = [my_missing >= 0 ? missing_value_from_offset(my_missing) : my_value];
      }
      return;
    case "float":
      for (let i = output_start; i < my_end; i++, my_offset += row_width) {
        const my_raw = view.getUint32(my_offset, little_endian);
        const my_missing = float_missing_offset(
          my_raw,
          modern_missing
        );
        rows[i] = [my_missing >= 0 ? missing_value_from_offset(my_missing) : view.getFloat32(my_offset, little_endian)];
      }
      return;
    case "double":
      for (let i = output_start; i < my_end; i++, my_offset += row_width) {
        const my_missing = double_missing_offset_for_version(
          view,
          my_offset,
          little_endian,
          format_version
        );
        rows[i] = [my_missing >= 0 ? missing_value_from_offset(my_missing) : view.getFloat64(my_offset, little_endian)];
      }
      return;
    case "strL":
      for (let i = output_start; i < my_end; i++) {
        rows[i] = [STRL_PLACEHOLDER];
      }
      return;
    default:
      for (let i = output_start; i < my_end; i++, my_offset += row_width) {
        rows[i] = [read_fixed_string3(
          bytes,
          my_offset,
          variable.byte_width,
          decoder
        )];
      }
  }
}
function read_rows_from_view(view, bytes, metadata, row_base_offset, start, count, col_start, col_end, out, out_offset = 0) {
  if (metadata.nobs === 0 || start < 0 || count <= 0 || start >= metadata.nobs) {
    return out ?? [];
  }
  const my_actual_count = Math.min(count, metadata.nobs - start);
  const my_col_start = Math.max(0, col_start ?? 0);
  const my_col_end = Math.min(
    metadata.nvar,
    col_end ?? metadata.nvar
  );
  if (my_col_start >= my_col_end) return out ?? [];
  const little_endian = metadata.byte_order === "LSF";
  const modern_missing = metadata.format_version >= 113;
  const my_decoder = decoder_for_metadata(metadata);
  const the_rows = out ?? new Array(my_actual_count);
  const my_column_count = my_col_end - my_col_start;
  if (my_column_count === 1) {
    decode_single_column_into_rows(
      view,
      bytes,
      the_rows,
      out_offset,
      my_actual_count,
      row_base_offset,
      metadata.variables[my_col_start],
      metadata.obs_length,
      little_endian,
      modern_missing,
      my_decoder,
      metadata.format_version
    );
    return the_rows;
  }
  for (let i = 0; i < my_actual_count; i++) {
    const my_row = new Array(my_column_count);
    const my_row_offset = row_base_offset + i * metadata.obs_length;
    for (let my_abs_col = my_col_start, my_output_col = 0; my_abs_col < my_col_end; my_abs_col++, my_output_col++) {
      const my_variable = metadata.variables[my_abs_col];
      my_row[my_output_col] = read_cell(
        view,
        bytes,
        my_row_offset + my_variable.byte_offset,
        my_variable,
        little_endian,
        modern_missing,
        my_decoder,
        metadata.format_version
      );
    }
    the_rows[out_offset + i] = my_row;
  }
  return the_rows;
}
function read_rows_from_data_buffer(buffer, metadata, start, count, col_start, col_end, out, out_offset = 0) {
  assert_valid_row_range(start, count);
  const { view, bytes } = buffer_views(buffer);
  return read_rows_from_view(
    view,
    bytes,
    metadata,
    0,
    start,
    count,
    col_start,
    col_end,
    out,
    out_offset
  );
}
function read_columns_from_data_buffer(buffer, metadata, count, col_indices, out, out_offset, write_strl_placeholders = true) {
  if (!Number.isInteger(count)) {
    throw new RangeError("Row count must be an integer");
  }
  if (count <= 0 || col_indices.length === 0) return;
  const { view, bytes } = buffer_views(buffer);
  const little_endian = metadata.byte_order === "LSF";
  const modern_missing = metadata.format_version >= 113;
  const my_decoder = decoder_for_metadata(metadata);
  for (const my_col of col_indices) {
    const my_target = out.get(my_col);
    decode_column_into_values(
      view,
      bytes,
      my_target,
      out_offset ?? my_target.length,
      count,
      metadata.variables[my_col],
      metadata.obs_length,
      little_endian,
      modern_missing,
      my_decoder,
      metadata.format_version,
      write_strl_placeholders
    );
  }
}

// src/strl-reader.ts
var GSO_MARKER = [71, 83, 79];
var STRLS_TAG = "<strls>";
var STRLS_TAG_LENGTH = STRLS_TAG.length;
var ASCII_DECODER2 = new TextDecoder("utf-8");
function build_gso_index(buffer, metadata, base_offset = 0) {
  const my_index = /* @__PURE__ */ new Map();
  const my_has_strl = metadata.variables.some(
    (v) => v.type === "strL"
  );
  if (!my_has_strl) return my_index;
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  const little_endian = metadata.byte_order === "LSF";
  const my_section_start = metadata.section_offsets.strls - base_offset;
  if (my_section_start < 0 || my_section_start + STRLS_TAG_LENGTH > bytes.length || ASCII_DECODER2.decode(bytes.subarray(
    my_section_start,
    my_section_start + STRLS_TAG_LENGTH
  )) !== STRLS_TAG) {
    throw new Error("Invalid <strls> section opening tag");
  }
  let pos = my_section_start + STRLS_TAG_LENGTH;
  const my_section_end = metadata.section_offsets.value_labels - base_offset;
  const my_close_start = my_section_end - 8;
  if (my_close_start < pos || my_section_end > bytes.length || ASCII_DECODER2.decode(bytes.subarray(
    my_close_start,
    my_section_end
  )) !== "</strls>") {
    throw new Error("Invalid </strls> section closing tag");
  }
  while (pos < my_close_start) {
    if (pos + 3 > my_close_start || bytes[pos] !== GSO_MARKER[0] || bytes[pos + 1] !== GSO_MARKER[1] || bytes[pos + 2] !== GSO_MARKER[2]) {
      throw new Error(`Invalid GSO marker at offset ${pos + base_offset}`);
    }
    pos += 3;
    const my_header_tail = metadata.format_version === 117 ? 13 : 17;
    if (pos + my_header_tail > my_close_start) {
      throw new Error("Truncated GSO header");
    }
    const my_v = view.getUint32(pos, little_endian);
    pos += 4;
    let my_o;
    if (metadata.format_version === 117) {
      my_o = view.getUint32(pos, little_endian);
      pos += 4;
    } else {
      const my_hi = little_endian ? view.getUint32(pos + 4, true) : view.getUint32(pos, false);
      const my_lo = little_endian ? view.getUint32(pos, true) : view.getUint32(pos + 4, false);
      if (my_hi > 2097151) {
        throw new Error(
          "strL observation number exceeds JavaScript safe integer range"
        );
      }
      my_o = my_hi * 4294967296 + my_lo;
      pos += 8;
    }
    const my_variable = metadata.variables[my_v - 1];
    if (my_v < 1 || my_o < 1 || my_o > metadata.nobs || !my_variable || my_variable.type !== "strL") {
      throw new Error(`Invalid GSO key ${my_v}:${my_o}`);
    }
    const my_type = bytes[pos];
    if (my_type !== 129 && my_type !== 130) {
      throw new Error(`Unsupported GSO type ${my_type}`);
    }
    pos += 1;
    const my_len = view.getUint32(pos, little_endian);
    pos += 4;
    if (pos + my_len > my_close_start) {
      throw new Error("Truncated GSO content");
    }
    if (my_type === 130 && (my_len === 0 || bytes[pos + my_len - 1] !== 0)) {
      throw new Error("Type-130 GSO content is not NUL-terminated");
    }
    const my_key = my_v + ":" + my_o;
    if (my_index.has(my_key)) {
      throw new Error(`Duplicate GSO key ${my_key}`);
    }
    my_index.set(my_key, {
      content_offset: pos,
      content_length: my_len,
      type: my_type
    });
    pos += my_len;
  }
  if (pos !== my_close_start) {
    throw new Error("Unexpected bytes in <strls> section");
  }
  return my_index;
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
  } else if (metadata.format_version === 118) {
    if (little_endian) {
      my_v = view.getUint16(pointer_offset, true);
      const my_lo = view.getUint32(
        pointer_offset + 2,
        true
      );
      const my_hi = view.getUint16(
        pointer_offset + 6,
        true
      );
      my_o = my_hi * 4294967296 + my_lo;
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
  } else if (little_endian) {
    my_v = view.getUint16(pointer_offset, true) + view.getUint8(pointer_offset + 2) * 65536;
    my_o = view.getUint32(pointer_offset + 3, true) + view.getUint8(pointer_offset + 7) * 4294967296;
  } else {
    my_v = view.getUint8(pointer_offset) * 65536 + view.getUint16(pointer_offset + 1, false);
    my_o = view.getUint8(pointer_offset + 3) * 4294967296 + view.getUint32(pointer_offset + 4, false);
  }
  if (my_v === 0 && my_o === 0) {
    return null;
  }
  const my_variable = metadata.variables[my_v - 1];
  if (my_v < 1 || my_o < 1 || my_o > metadata.nobs || !my_variable || my_variable.type !== "strL") {
    throw new Error(`Invalid strL pointer ${my_v}:${my_o}`);
  }
  return { v: my_v, o: my_o };
}
function decode_gso_entry(bytes, entry, encoding = "utf-8") {
  if (entry.type !== 129 && entry.type !== 130) {
    throw new Error(`Unsupported GSO type ${entry.type}`);
  }
  const my_content_end = entry.content_offset + entry.content_length;
  if (entry.content_offset < 0 || entry.content_length < 0 || my_content_end > bytes.length) {
    throw new Error("Truncated GSO content");
  }
  if (entry.type === 130) {
    if (entry.content_length === 0 || bytes[my_content_end - 1] !== 0) {
      throw new Error(
        "Type-130 GSO content is not NUL-terminated"
      );
    }
    const my_str_len = entry.content_length - 1;
    return text_decoder(encoding).decode(
      bytes.subarray(
        entry.content_offset,
        entry.content_offset + my_str_len
      )
    );
  }
  return text_decoder(encoding).decode(
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
var MODERN_LABEL_NAME_WIDTH = {
  117: 33,
  118: 129,
  119: 129
};
var PADDING_BYTES = 3;
function parse_label_entry_payload(bytes, view, little_endian, pos, entry_end, decoder) {
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
  const my_offsets_start = pos;
  const my_values_start = my_offsets_start + my_n * 4;
  const my_text_start = my_values_start + my_n * 4;
  const my_label_map = /* @__PURE__ */ new Map();
  for (let i = 0; i < my_n; i++) {
    const my_text_offset = view.getInt32(
      my_offsets_start + i * 4,
      little_endian
    );
    if (my_text_offset < 0 || my_text_offset >= my_txt_len) {
      throw new Error(
        "Corrupt value label table: invalid text offset"
      );
    }
    const my_str_start = my_text_start + my_text_offset;
    let my_str_end = my_str_start;
    const my_str_limit = my_text_start + my_txt_len;
    while (my_str_end < my_str_limit && bytes[my_str_end] !== 0) {
      my_str_end++;
    }
    if (my_str_end === my_str_limit) {
      throw new Error(
        "Corrupt value label table: missing text terminator"
      );
    }
    const my_label = decode_text_range(
      decoder,
      bytes,
      my_str_start,
      my_str_end
    );
    const my_value = view.getInt32(
      my_values_start + i * 4,
      little_endian
    );
    if (!my_label_map.has(my_value)) {
      my_label_map.set(my_value, my_label);
    }
  }
  return {
    label_map: my_label_map,
    next_pos: my_text_start + my_txt_len
  };
}
function read_label_name(bytes, pos, name_width, decoder) {
  let my_end = pos;
  const my_limit = pos + name_width;
  while (my_end < my_limit && bytes[my_end] !== 0) {
    my_end++;
  }
  return decode_text_range(decoder, bytes, pos, my_end);
}
function parse_modern_entries(bytes, view, little_endian, name_width, start_pos, section_end, decoder) {
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
      name_width,
      decoder
    );
    pos += name_width;
    pos += PADDING_BYTES;
    const { label_map, next_pos } = parse_label_entry_payload(
      bytes,
      view,
      little_endian,
      pos,
      section_end,
      decoder
    );
    my_result.set(my_label_name, label_map);
    pos = next_pos + LBL_CLOSE_TAG_LENGTH;
  }
  return my_result;
}
function parse_legacy_entries(bytes, view, little_endian, name_width, start_pos, section_end, decoder) {
  const my_result = /* @__PURE__ */ new Map();
  let pos = start_pos;
  let my_known_nonzero = -1;
  while (pos < section_end) {
    if (my_known_nonzero < pos) {
      my_known_nonzero = -1;
      for (let i = pos; i < section_end; i++) {
        if (bytes[i] !== 0) {
          my_known_nonzero = i;
          break;
        }
      }
    }
    if (my_known_nonzero < pos) break;
    if (pos + 4 > section_end) {
      throw new Error(
        "Corrupt value label table: trailing bytes"
      );
    }
    const my_table_len = view.getInt32(
      pos,
      little_endian
    );
    if (my_table_len <= 0) {
      throw new Error(
        "Corrupt value label table: invalid table length"
      );
    }
    pos += 4;
    const my_label_name = read_label_name(
      bytes,
      pos,
      name_width,
      decoder
    );
    pos += name_width;
    pos += PADDING_BYTES;
    const { label_map, next_pos } = parse_label_entry_payload(
      bytes,
      view,
      little_endian,
      pos,
      section_end,
      decoder
    );
    my_result.set(my_label_name, label_map);
    pos = next_pos;
  }
  return my_result;
}
function parse_fixed8_entries(bytes, view, little_endian, name_width, start_pos, section_end, decoder) {
  const my_result = /* @__PURE__ */ new Map();
  let pos = start_pos;
  let my_known_nonzero = -1;
  while (pos < section_end) {
    if (my_known_nonzero < pos) {
      my_known_nonzero = -1;
      for (let i = pos; i < section_end; i++) {
        if (bytes[i] !== 0) {
          my_known_nonzero = i;
          break;
        }
      }
    }
    if (my_known_nonzero < pos) break;
    const my_header_width = 2 + name_width + 1;
    if (pos + my_header_width > section_end) {
      throw new Error(
        "Corrupt value label table: trailing bytes"
      );
    }
    const my_n = view.getUint16(pos, little_endian);
    pos += 2;
    const my_name = read_label_name(
      bytes,
      pos,
      name_width,
      decoder
    );
    pos += name_width + 1;
    if (pos + my_n * 10 > section_end) {
      throw new Error(
        "Corrupt value label table: truncated entry"
      );
    }
    const the_codes = [];
    for (let i = 0; i < my_n; i++) {
      the_codes.push(view.getInt16(pos, little_endian));
      pos += 2;
    }
    const my_labels = /* @__PURE__ */ new Map();
    for (let i = 0; i < my_n; i++) {
      const my_label = read_label_name(
        bytes,
        pos,
        8,
        decoder
      );
      if (!my_labels.has(the_codes[i])) {
        my_labels.set(the_codes[i], my_label);
      }
      pos += 8;
    }
    my_result.set(my_name, my_labels);
  }
  return my_result;
}
function has_variable_label_table_framing(view, little_endian, start_pos, section_end, name_width) {
  const my_payload_start = start_pos + 4 + name_width + 3;
  if (my_payload_start + 8 > section_end) return false;
  const my_table_len = view.getInt32(start_pos, little_endian);
  const my_n = view.getInt32(my_payload_start, little_endian);
  const my_text_len = view.getInt32(
    my_payload_start + 4,
    little_endian
  );
  if (my_table_len <= 0 || my_n < 0 || my_text_len < 0) {
    return false;
  }
  const my_payload_len = 8 + my_n * 8 + my_text_len;
  return my_payload_len === my_table_len && my_payload_start + my_payload_len <= section_end;
}
function has_variable_label_section_framing(bytes, view, little_endian, start_pos, section_end, name_width) {
  const my_prefix_width = 4 + name_width + PADDING_BYTES;
  let pos = start_pos;
  let my_known_nonzero = -1;
  while (pos < section_end) {
    const my_header_end = Math.min(
      section_end,
      pos + my_prefix_width + 8
    );
    let my_header_has_nonzero = false;
    for (let i = pos; i < my_header_end; i++) {
      if (bytes[i] !== 0) {
        my_header_has_nonzero = true;
        break;
      }
    }
    if (!my_header_has_nonzero) {
      if (my_known_nonzero < pos) {
        my_known_nonzero = -1;
        for (let i = my_header_end; i < section_end; i++) {
          if (bytes[i] !== 0) {
            my_known_nonzero = i;
            break;
          }
        }
      }
      if (my_known_nonzero < pos) return true;
    }
    if (!has_variable_label_table_framing(
      view,
      little_endian,
      pos,
      section_end,
      name_width
    )) {
      return false;
    }
    const my_table_len = view.getInt32(pos, little_endian);
    const my_next = pos + my_prefix_width + my_table_len;
    if (my_next <= pos || my_next > section_end) return false;
    pos = my_next;
  }
  return true;
}
function parse_value_labels(buffer, metadata, base_offset = 0) {
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  const little_endian = metadata.byte_order === "LSF";
  const my_legacy = is_legacy_format(
    metadata.format_version
  );
  const my_decoder = text_decoder(resolve_text_encoding(
    metadata.format_version,
    metadata.text_encoding
  ));
  const my_tag_skip = my_legacy ? 0 : VALUE_LABELS_TAG_LENGTH;
  const my_start_pos = metadata.section_offsets.value_labels - base_offset + my_tag_skip;
  const my_section_end = metadata.section_offsets.stata_data_close - base_offset;
  if (is_legacy_format(metadata.format_version)) {
    const my_layout = legacy_layout_for_version(
      metadata.format_version
    );
    let my_value_label_layout = my_layout.value_label_layout;
    let my_name_width = my_layout.value_label_table_name_width;
    if (metadata.format_version === 105 && has_variable_label_section_framing(
      bytes,
      view,
      little_endian,
      my_start_pos,
      my_section_end,
      33
    )) {
      my_value_label_layout = "offset_table";
      my_name_width = 33;
    } else if (metadata.format_version === 108 && !has_variable_label_section_framing(
      bytes,
      view,
      little_endian,
      my_start_pos,
      my_section_end,
      9
    ) && has_variable_label_section_framing(
      bytes,
      view,
      little_endian,
      my_start_pos,
      my_section_end,
      33
    )) {
      my_name_width = 33;
    }
    if (my_value_label_layout === "fixed8") {
      return parse_fixed8_entries(
        bytes,
        view,
        little_endian,
        my_name_width,
        my_start_pos,
        my_section_end,
        my_decoder
      );
    }
    return parse_legacy_entries(
      bytes,
      view,
      little_endian,
      my_name_width,
      my_start_pos,
      my_section_end,
      my_decoder
    );
  }
  return parse_modern_entries(
    bytes,
    view,
    little_endian,
    MODERN_LABEL_NAME_WIDTH[metadata.format_version],
    my_start_pos,
    my_section_end,
    my_decoder
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

// src/node.ts
var MODERN_MAP_READ_SIZE = 128 * 1024;
var LEGACY_SCAN_BLOCK_SIZE = 64 * 1024;
var LEGACY_SCAN_SMALL_PAYLOAD = LEGACY_SCAN_BLOCK_SIZE / 8;
var MAX_LEGACY_METADATA_SIZE = 64 * 1024 * 1024;
var MAX_MODERN_METADATA_SIZE = 64 * 1024 * 1024;
var MAX_READ_RETRIES = 2;
var DATA_TAG_LENGTH2 = "<data>".length;
var DEFAULT_CHUNK_ROWS = 65536;
var DEFAULT_CHUNK_BYTES = 16 * 1024 * 1024;
function throw_if_aborted(signal) {
  if (signal.aborted) {
    throw new DOMException(
      "The read was aborted",
      "AbortError"
    );
  }
}
function yield_to_event_loop() {
  return new Promise((resolve) => setImmediate(resolve));
}
function normalise_chunk_rows(requested_chunk_rows, row_width, cancellable) {
  if (typeof requested_chunk_rows === "number" && Number.isInteger(requested_chunk_rows) && requested_chunk_rows >= 1) {
    return requested_chunk_rows;
  }
  const my_byte_bounded_rows = row_width > 0 ? Math.max(1, Math.floor(DEFAULT_CHUNK_BYTES / row_width)) : DEFAULT_CHUNK_ROWS;
  return cancellable ? Math.min(DEFAULT_CHUNK_ROWS, my_byte_bounded_rows) : my_byte_bounded_rows;
}
function normalise_column_indices(col_indices, nvar) {
  const the_seen = /* @__PURE__ */ new Set();
  const the_columns = [];
  for (const my_col of col_indices) {
    if (!Number.isInteger(my_col)) {
      throw new Error(
        `Column index ${my_col} must be an integer`
      );
    }
    if (my_col < 0 || my_col >= nvar) {
      throw new Error(
        `Column index ${my_col} is out of bounds for ${nvar} columns`
      );
    }
    if (!the_seen.has(my_col)) {
      the_seen.add(my_col);
      the_columns.push(my_col);
    }
  }
  return the_columns;
}
var DtaFile = class _DtaFile {
  _fd;
  _metadata;
  // strL (GSO) state, populated lazily by `_ensure_gso()` the first
  // time an strL cell is actually resolved. Files without strL columns,
  // and reads that never touch an strL column, never read or retain the
  // section. Once loaded, the section bytes stay resident so each cell
  // resolves with an in-memory slice + decode rather than a per-cell
  // disk read.
  _gso_index;
  _gso_section;
  _gso_loaded;
  _value_label_tables;
  _closed;
  // Precomputed: column indices of strL variables
  _strl_col_indices;
  // Same set, for O(1) membership tests in per-column reads
  _strl_col_set;
  constructor(fd, metadata, value_label_tables) {
    this._fd = fd;
    this._metadata = metadata;
    this._gso_index = /* @__PURE__ */ new Map();
    this._gso_section = null;
    this._gso_loaded = false;
    this._value_label_tables = value_label_tables;
    this._closed = false;
    const the_indices = [];
    for (let i = 0; i < metadata.variables.length; i++) {
      if (metadata.variables[i].type === "strL") {
        the_indices.push(i);
      }
    }
    this._strl_col_indices = the_indices;
    this._strl_col_set = new Set(the_indices);
  }
  /**
   * Open a .dta file and parse all metadata.
   *
   * Keeps the file descriptor open for fd-backed random
   * access. Only metadata and sidecar sections are loaded
   * into memory; observation rows are read on demand.
   */
  static async open(file_path, options = {}) {
    const my_fd = fs.openSync(file_path, "r");
    try {
      validate_text_encoding(options.encoding);
      const my_file_size = fs.fstatSync(my_fd).size;
      const my_metadata = detect_and_parse_metadata(
        my_fd,
        my_file_size,
        options
      );
      const my_labels = read_value_labels(
        my_fd,
        my_metadata
      );
      return new _DtaFile(
        my_fd,
        my_metadata,
        my_labels
      );
    } catch (my_err) {
      fs.closeSync(my_fd);
      throw my_err;
    }
  }
  // -------------------------------------------------------
  // Public accessors
  // -------------------------------------------------------
  /** Stata on-disk format release. */
  get format_version() {
    return this._metadata.format_version;
  }
  /** Resolved source encoding used for textual fields. */
  get text_encoding() {
    return resolve_text_encoding(
      this._metadata.format_version,
      this._metadata.text_encoding
    );
  }
  /** Number of observations (rows). */
  get nobs() {
    return this._metadata.nobs;
  }
  /** Number of variables (columns). */
  get nvar() {
    return this._metadata.nvar;
  }
  /** Variable metadata array. */
  get variables() {
    return this._metadata.variables;
  }
  /** Complete metadata, including dataset-scoped notes and characteristics. */
  get metadata() {
    return this._metadata;
  }
  /** Dataset label string. */
  get dataset_label() {
    return this._metadata.dataset_label;
  }
  /** Value label tables (table_name -> value -> label). */
  get value_label_tables() {
    return this._value_label_tables;
  }
  // -------------------------------------------------------
  // Data reading
  // -------------------------------------------------------
  /**
   * Read observation rows, resolving strL pointers.
   *
   * @param start - First row index (0-based)
   * @param count - Number of rows to read
   * @param col_start - First column (inclusive, optional)
   * @param col_end - Last column (exclusive, optional)
   * @param options - Cancellation options (see {@link ReadRowsOptions}).
   *   When `options.signal` is provided, the read is chunked and
   *   yields between chunks so the abort can be observed; it rejects
   *   with an `AbortError` if the signal fires. Without a signal, chunks
   *   run synchronously and bound the temporary observation buffer.
   */
  async read_rows(start, count, col_start, col_end, options) {
    if (this._closed || this._fd === null) return [];
    assert_valid_row_range(start, count);
    if (this._metadata.nobs === 0 || start < 0 || count <= 0 || start >= this._metadata.nobs) {
      return [];
    }
    const my_actual_count = Math.min(
      count,
      this._metadata.nobs - start
    );
    const my_signal = options?.signal;
    const my_chunk_rows = normalise_chunk_rows(
      options?.chunk_rows,
      this._metadata.obs_length,
      my_signal !== void 0
    );
    if (my_signal) throw_if_aborted(my_signal);
    const my_col_start = Math.max(0, col_start ?? 0);
    const my_col_end = Math.min(
      this._metadata.nvar,
      col_end ?? this._metadata.nvar
    );
    if (my_col_start >= my_col_end) return [];
    const the_rows = my_signal ? [] : new Array(my_actual_count);
    const my_complete = await this._for_each_observation_chunk(
      start,
      my_actual_count,
      my_chunk_rows,
      my_signal,
      (my_data_buffer, my_chunk_start, my_chunk_count, my_output_offset) => {
        this._decode_rows_range(
          my_data_buffer,
          my_chunk_start,
          my_chunk_count,
          my_col_start,
          my_col_end,
          the_rows,
          my_output_offset
        );
      }
    );
    return my_complete ? the_rows : [];
  }
  /**
   * Read multiple columns in a single pass over the data section,
   * parsing only the requested columns.
   *
   * @param col_indices - Distinct or repeated 0-based column indices.
   *   Repeats are deduplicated, and the returned map is keyed by the
   *   requested absolute column indices.
   * @param options - Chunking and cancellation options.
   * @returns A map keyed by the requested distinct column indices, each
   *   mapping to that column's value for every observation. A closed
   *   file (at entry or closed mid-read) yields an empty map with NO
   *   keys — deliberately distinct from the keyed-but-empty map returned
   *   for an empty request or a zero-row dataset. Callers must treat a
   *   missing key as "not read" (e.g. fall back to reading that column
   *   directly) rather than assuming every requested key is present.
   */
  async read_columns(col_indices, options) {
    if (this._closed || this._fd === null) {
      return /* @__PURE__ */ new Map();
    }
    const the_columns = normalise_column_indices(
      col_indices,
      this._metadata.nvar
    );
    const my_signal = options?.signal;
    if (my_signal && the_columns.length > 0 && this._metadata.nobs > 0) {
      throw_if_aborted(my_signal);
    }
    const the_values = /* @__PURE__ */ new Map();
    for (const my_col of the_columns) {
      the_values.set(
        my_col,
        my_signal ? [] : new Array(this._metadata.nobs)
      );
    }
    if (the_columns.length === 0 || this._metadata.nobs === 0) {
      return the_values;
    }
    const my_chunk_rows = normalise_chunk_rows(
      options?.chunk_rows,
      this._metadata.obs_length,
      my_signal !== void 0
    );
    const my_complete = await this._for_each_observation_chunk(
      0,
      this._metadata.nobs,
      my_chunk_rows,
      my_signal,
      (my_data_buffer, _my_chunk_start, my_chunk_count, my_output_offset) => {
        read_columns_from_data_buffer(
          my_data_buffer,
          this._metadata,
          my_chunk_count,
          the_columns,
          the_values,
          my_output_offset,
          false
        );
        for (const my_col of the_columns) {
          if (this._strl_col_set.has(my_col)) {
            this._resolve_strl_column(
              the_values.get(my_col),
              my_output_offset,
              my_data_buffer,
              my_col,
              my_chunk_count
            );
          }
        }
      }
    );
    return my_complete ? the_values : /* @__PURE__ */ new Map();
  }
  /** Decode one observation chunk directly into the caller's row array. */
  _decode_rows_range(data_buffer, start, count, col_start, col_end, out, out_offset) {
    read_rows_from_data_buffer(
      data_buffer,
      this._metadata,
      start,
      count,
      col_start,
      col_end,
      out,
      out_offset
    );
    if (this._strl_col_indices.length > 0) {
      this._resolve_strls(
        out,
        data_buffer,
        col_start,
        col_end,
        out_offset,
        count
      );
    }
  }
  /**
   * Read contiguous observation chunks and centralize yielding,
   * cancellation, and close handling for every output layout.
   */
  async _for_each_observation_chunk(start, count, chunk_rows, signal, consume) {
    let my_read = 0;
    while (my_read < count) {
      if (my_read > 0 && signal) {
        await yield_to_event_loop();
        throw_if_aborted(signal);
      }
      if (this._closed || this._fd === null) {
        return false;
      }
      const my_chunk_count = Math.min(
        chunk_rows,
        count - my_read
      );
      const my_chunk_start = start + my_read;
      const my_data_buffer = read_data_rows(
        this._fd,
        this._metadata,
        my_chunk_start,
        my_chunk_count
      );
      consume(
        my_data_buffer,
        my_chunk_start,
        my_chunk_count,
        my_read
      );
      my_read += my_chunk_count;
    }
    if (signal) throw_if_aborted(signal);
    return true;
  }
  // -------------------------------------------------------
  // Resource management
  // -------------------------------------------------------
  /**
   * Release the open file handle and internal caches.
   * After close, read_rows returns empty arrays.
   */
  close() {
    if (this._fd !== null) {
      fs.closeSync(this._fd);
      this._fd = null;
    }
    this._closed = true;
    this._gso_index = /* @__PURE__ */ new Map();
    this._gso_section = null;
    this._value_label_tables = /* @__PURE__ */ new Map();
  }
  // -------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------
  /**
   * Lazily read and index the strL (GSO) section on first use. Called
   * only from the strL resolution paths, so a file whose strL columns
   * are never read pays nothing: the section is neither read nor
   * retained. The whole section is read once (a single sequential
   * read) and kept resident so subsequent cells resolve from memory.
   */
  _ensure_gso() {
    if (this._gso_loaded) return;
    if (this._fd === null || this._strl_col_indices.length === 0) {
      this._gso_loaded = true;
      return;
    }
    const my_start = this._metadata.section_offsets.strls;
    const my_length = this._metadata.section_offsets.value_labels - my_start;
    if (my_length <= 0) {
      this._gso_loaded = true;
      return;
    }
    const my_buffer = read_range(
      this._fd,
      my_start,
      my_length
    );
    this._gso_index = build_gso_index(
      my_buffer,
      this._metadata,
      my_start
    );
    this._gso_section = new Uint8Array(my_buffer);
    this._gso_loaded = true;
  }
  /**
   * Post-process rows to resolve strL placeholders.
   *
   * For each strL column in the requested range, decode the pointer
   * from the row buffer and resolve the GSO payload from the
   * in-memory strL section (no per-cell disk reads).
   */
  _resolve_strls(the_rows, data_buffer, col_start, col_end, row_start, row_count) {
    if (this._fd === null) return;
    const my_has_strl_in_range = this._strl_col_indices.some(
      (my_col) => my_col >= col_start && my_col < col_end
    );
    if (!my_has_strl_in_range) return;
    this._ensure_gso();
    const my_view = data_buffer_view(data_buffer);
    for (const my_abs_col of this._strl_col_indices) {
      if (my_abs_col < col_start || my_abs_col >= col_end) {
        continue;
      }
      const my_row_col = my_abs_col - col_start;
      const my_var = this._metadata.variables[my_abs_col];
      for (let i = 0; i < row_count; i++) {
        const my_pointer_offset = i * this._metadata.obs_length + my_var.byte_offset;
        the_rows[row_start + i][my_row_col] = this._resolve_strl_at(
          my_view,
          my_pointer_offset
        );
      }
    }
  }
  /**
   * Resolve the strL placeholders of one column, in place, into a
   * flat column array. Used by the single-pass read_columns path,
   * where `read_columns_from_data_buffer` first fills the column
   * with placeholders. `base_index` is where this chunk's values
   * begin in `col_values`.
   */
  _resolve_strl_column(col_values, base_index, data_buffer, abs_col, count) {
    this._ensure_gso();
    const my_view = data_buffer_view(data_buffer);
    const my_var = this._metadata.variables[abs_col];
    for (let i = 0; i < count; i++) {
      const my_pointer_offset = i * this._metadata.obs_length + my_var.byte_offset;
      col_values[base_index + i] = this._resolve_strl_at(
        my_view,
        my_pointer_offset
      );
    }
  }
  /**
   * Resolve a single strL pointer at `pointer_offset` within the
   * chunk's data buffer to its string value, reading the GSO payload
   * from the in-memory strL section. Returns '' only for a null pointer;
   * a missing non-null key is corrupt input.
   */
  _resolve_strl_at(view, pointer_offset) {
    const my_pointer = read_strl_pointer(
      view,
      this._metadata,
      pointer_offset
    );
    if (!my_pointer) return "";
    const my_entry = this._gso_index.get(
      my_pointer.v + ":" + my_pointer.o
    );
    if (!my_entry || this._gso_section === null) {
      throw new Error(
        `Dangling strL pointer ${my_pointer.v}:${my_pointer.o}`
      );
    }
    return decode_gso_entry(
      this._gso_section,
      my_entry,
      this.text_encoding
    );
  }
};
var LEGACY_VERSION_BYTES = /* @__PURE__ */ new Set([105, 108, 110, 111, 113, 114, 115]);
var MIN_LEGACY_HEADER = 10;
function detect_and_parse_metadata(fd, file_size, options) {
  if (file_size < 1) {
    throw new Error(
      "Not a valid .dta file: file is empty"
    );
  }
  const my_probe = read_range(fd, 0, 1);
  const my_first_byte = new Uint8Array(my_probe)[0];
  if (LEGACY_VERSION_BYTES.has(my_first_byte)) {
    return read_legacy_metadata(fd, file_size, options);
  }
  return read_modern_metadata(fd, file_size, options);
}
function read_legacy_metadata(fd, file_size, options) {
  if (file_size < MIN_LEGACY_HEADER) {
    throw new Error(
      "Not a valid .dta file: too small for legacy header"
    );
  }
  const my_header = read_range(
    fd,
    0,
    Math.min(file_size, MIN_LEGACY_HEADER)
  );
  const my_header_bytes = new Uint8Array(my_header);
  const my_version = my_header_bytes[0];
  const my_byte_order_code = my_header_bytes[1];
  if (my_byte_order_code !== 1 && my_byte_order_code !== 2) {
    throw new Error(`Invalid byte order code: ${my_byte_order_code}`);
  }
  if (my_header_bytes[2] !== 1) {
    throw new Error(`Invalid legacy file type: ${my_header_bytes[2]}`);
  }
  const my_little_endian = my_byte_order_code === 2;
  const my_header_view = new DataView(my_header);
  const my_nvar = my_header_view.getUint16(
    4,
    my_little_endian
  );
  const layout = legacy_layout_for_version(my_version);
  const my_expansion_start = legacy_metadata_fixed_size(
    my_nvar,
    my_version
  );
  const my_field_header_size = legacy_expansion_header_size(layout);
  if (my_expansion_start > file_size) {
    throw new Error("Truncated legacy metadata");
  }
  let my_position = my_expansion_start;
  const my_scan_buffer = Buffer.allocUnsafe(LEGACY_SCAN_BLOCK_SIZE);
  const my_header_buffer = Buffer.allocUnsafe(my_field_header_size);
  let my_scan_start = -1;
  let my_scan_length = 0;
  while (true) {
    if (my_position + my_field_header_size > file_size) {
      throw new Error("Missing legacy expansion-field terminator");
    }
    const my_record_start = my_position;
    const my_uses_scan_buffer = my_position >= my_scan_start && my_position + my_field_header_size <= my_scan_start + my_scan_length;
    let my_header_bytes2;
    let my_header_offset;
    if (my_uses_scan_buffer) {
      my_header_bytes2 = my_scan_buffer;
      my_header_offset = my_position - my_scan_start;
    } else {
      read_bytes_into(
        fd,
        my_header_buffer,
        0,
        my_field_header_size,
        my_position
      );
      my_header_bytes2 = my_header_buffer;
      my_header_offset = 0;
    }
    const my_data_type = my_header_bytes2[my_header_offset];
    const my_length = layout.expansion_length_width === 2 ? my_little_endian ? my_header_bytes2.readInt16LE(my_header_offset + 1) : my_header_bytes2.readInt16BE(my_header_offset + 1) : my_little_endian ? my_header_bytes2.readInt32LE(my_header_offset + 1) : my_header_bytes2.readInt32BE(my_header_offset + 1);
    my_position += my_field_header_size;
    if (my_data_type === 0 && my_length === 0) break;
    if (my_data_type === 0 || my_length < 0) {
      throw new Error("Invalid legacy expansion field");
    }
    if (my_length > file_size - my_position) {
      throw new Error("Truncated legacy expansion field");
    }
    if (!my_uses_scan_buffer && my_length <= LEGACY_SCAN_SMALL_PAYLOAD) {
      my_scan_start = my_record_start;
      my_scan_length = Math.min(
        LEGACY_SCAN_BLOCK_SIZE,
        file_size - my_scan_start
      );
      read_bytes_into(
        fd,
        my_scan_buffer,
        0,
        my_scan_length,
        my_scan_start
      );
    }
    my_position += my_length;
    if (my_position > MAX_LEGACY_METADATA_SIZE) {
      throw new Error("Legacy metadata exceeds 64 MiB safety limit");
    }
  }
  const my_buffer = read_range(fd, 0, my_position);
  return parse_legacy_metadata(my_buffer, file_size, options);
}
function read_modern_metadata(fd, file_size, options) {
  const map_buffer = read_range(
    fd,
    0,
    Math.min(file_size, MODERN_MAP_READ_SIZE)
  );
  let header;
  try {
    header = parse_modern_metadata_header(map_buffer, options);
  } catch (error) {
    if (error instanceof Error && error.message.includes("unrecognized format signature")) {
      throw new Error(
        "Unsupported .dta format: only Stata 5+ files (formats 105, 108, 110-111, 113-115 and 117-119) are supported"
      );
    }
    throw error;
  }
  const metadata_size = header.section_offsets.data;
  if (metadata_size > MAX_MODERN_METADATA_SIZE) {
    throw new Error("Modern metadata exceeds 64 MiB safety limit");
  }
  if (metadata_size > file_size) {
    throw new Error("Truncated modern metadata");
  }
  let metadata_buffer;
  if (metadata_size <= map_buffer.byteLength) {
    metadata_buffer = map_buffer.slice(0, metadata_size);
  } else {
    metadata_buffer = new ArrayBuffer(metadata_size);
    const metadata_bytes = new Uint8Array(metadata_buffer);
    metadata_bytes.set(new Uint8Array(map_buffer));
    read_bytes_into(
      fd,
      metadata_bytes,
      map_buffer.byteLength,
      metadata_size - map_buffer.byteLength,
      map_buffer.byteLength
    );
  }
  return parse_metadata_from_header(metadata_buffer, header);
}
function read_value_labels(fd, metadata) {
  const my_section_start = metadata.section_offsets.value_labels;
  const my_section_length = metadata.section_offsets.end_of_file - metadata.section_offsets.value_labels;
  if (my_section_length <= 0) {
    return /* @__PURE__ */ new Map();
  }
  const my_buffer = read_range(
    fd,
    my_section_start,
    my_section_length
  );
  return parse_value_labels(
    my_buffer,
    metadata,
    my_section_start
  );
}
function read_data_rows(fd, metadata, start, count) {
  const my_tag_length = is_legacy_format(
    metadata.format_version
  ) ? 0 : DATA_TAG_LENGTH2;
  const my_offset = metadata.section_offsets.data + my_tag_length + start * metadata.obs_length;
  const my_length = count * metadata.obs_length;
  return read_bytes(fd, my_offset, my_length);
}
function read_bytes(fd, offset, length) {
  const my_buffer = Buffer.allocUnsafe(length);
  read_bytes_into(fd, my_buffer, 0, length, offset);
  return my_buffer;
}
function read_bytes_into(fd, target, target_offset, length, file_offset) {
  let my_total_read = 0;
  let my_attempts = 0;
  while (my_total_read < length) {
    const my_bytes_read = fs.readSync(
      fd,
      target,
      target_offset + my_total_read,
      length - my_total_read,
      file_offset + my_total_read
    );
    if (my_bytes_read === 0) {
      my_attempts++;
      if (my_attempts > MAX_READ_RETRIES) {
        throw new Error(
          `Unexpected EOF while reading ${length} bytes at offset ${file_offset}`
        );
      }
      continue;
    }
    my_total_read += my_bytes_read;
  }
}
function read_range(fd, offset, length) {
  const my_bytes = read_bytes(fd, offset, length);
  if (my_bytes.buffer instanceof ArrayBuffer && my_bytes.byteOffset === 0 && my_bytes.byteLength === my_bytes.buffer.byteLength) {
    return my_bytes.buffer;
  }
  return my_bytes.buffer.slice(
    my_bytes.byteOffset,
    my_bytes.byteOffset + my_bytes.byteLength
  );
}
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  DtaFile,
  STATA_MISSING_B,
  addStataNote,
  apply_display_format,
  classify_missing_value,
  classify_raw_double_missing_at,
  classify_raw_float_missing,
  dropStataCharacteristics,
  dropStataNotes,
  getStataCharacteristic,
  getStataNote,
  is_legacy_format,
  is_missing_value,
  is_missing_value_object,
  listStataCharacteristics,
  listStataNotes,
  make_missing_value,
  missing_type_to_label_key,
  renumberStataNotes,
  setStataCharacteristic,
  setStataNote
});
