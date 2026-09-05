var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
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
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// src/index.ts
var index_exports = {};
__export(index_exports, {
  ArrowBuffer: () => ArrowBuffer,
  DTA_MISSING_B: () => DTA_MISSING_B,
  addStataNote: () => addStataNote,
  apply_display_format: () => apply_display_format,
  build_gso_index: () => build_gso_index,
  classify_missing_value: () => classify_missing_value,
  classify_raw_double_missing_at: () => classify_raw_double_missing_at,
  classify_raw_float_missing: () => classify_raw_float_missing,
  decode_gso_entry: () => decode_gso_entry,
  dropStataCharacteristics: () => dropStataCharacteristics,
  dropStataNotes: () => dropStataNotes,
  getStataCharacteristic: () => getStataCharacteristic,
  getStataNote: () => getStataNote,
  is_legacy_format: () => is_legacy_format,
  is_missing_value: () => is_missing_value,
  is_missing_value_object: () => is_missing_value_object,
  legacy_metadata_buffer_size: () => legacy_metadata_buffer_size,
  listStataCharacteristics: () => listStataCharacteristics,
  listStataNotes: () => listStataNotes,
  make_missing_value: () => make_missing_value,
  missing_type_to_label_key: () => missing_type_to_label_key,
  parse_legacy_metadata: () => parse_legacy_metadata,
  parse_metadata: () => parse_metadata,
  parse_value_labels: () => parse_value_labels,
  read_rows_from_buffer: () => read_rows_from_buffer,
  read_rows_from_data_buffer: () => read_rows_from_data_buffer,
  read_strl_pointer: () => read_strl_pointer,
  renumberStataNotes: () => renumberStataNotes,
  resolve_strl: () => resolve_strl,
  resolve_text_encoding: () => resolve_text_encoding,
  setStataCharacteristic: () => setStataCharacteristic,
  setStataNote: () => setStataNote
});
module.exports = __toCommonJS(index_exports);

// src/types.ts
var FORMAT_SIGNATURES = {
  117: "<stata_dta><header><release>117</release>",
  118: "<stata_dta><header><release>118</release>",
  119: "<stata_dta><header><release>119</release>"
};
var LEGACY_FORMAT_SET = /* @__PURE__ */ new Set([105, 108, 110, 111, 113, 114, 115]);
function is_legacy_format(version2) {
  return LEGACY_FORMAT_SET.has(version2);
}
var MODERN_TYPE_CODES = {
  65530: { type: "byte", width: 1 },
  65529: { type: "int", width: 2 },
  65528: { type: "long", width: 4 },
  65527: { type: "float", width: 4 },
  65526: { type: "double", width: 8 },
  32768: { type: "strL", width: 8 }
};
var MAX_STR_WIDTH_MODERN = 2045;
function byte_width_for_type_code(code, format_version) {
  const my_entry = MODERN_TYPE_CODES[code];
  if (my_entry) return my_entry.width;
  if (Number.isInteger(code) && code >= 1 && code <= MAX_STR_WIDTH_MODERN) return code;
  throw new Error(
    `Unknown type code ${code} for format v${format_version}`
  );
}
function type_code_to_dta_type(code, format_version) {
  const my_entry = MODERN_TYPE_CODES[code];
  if (my_entry) return my_entry.type;
  if (Number.isInteger(code) && code >= 1 && code <= MAX_STR_WIDTH_MODERN) return `str${code}`;
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
function isPackedDtaReadPlan(metadata2) {
  return "variable_types" in metadata2;
}

// src/text-encoding.ts
function decode_text_range(decoder2, bytes, start, end) {
  if (start < 0 || end > bytes.length) {
    return decoder2.decode(bytes.subarray(start, end));
  }
  const my_length = end - start;
  if (my_length > 12) {
    return decoder2.decode(bytes.subarray(start, end));
  }
  for (let i = start; i < end; i++) {
    if (bytes[i] >= 128) {
      return decoder2.decode(bytes.subarray(start, end));
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
      return decoder2.decode(bytes.subarray(start, end));
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

// src/dta-metadata.ts
var NOTE_NAME = /^note([0-9]+)$/;
var MAX_DTA_METADATA_VALUE_BYTES = 67784;
var MAX_DECODED_DTA_METADATA_VALUE_BYTES = 203352;
var TEXT_ENCODER = new TextEncoder();
var LAZY_NOTES = /* @__PURE__ */ new WeakMap();
var LAZY_CHARACTERISTICS = /* @__PURE__ */ new WeakMap();
function lazyNotes() {
  let notes = LAZY_NOTES.get(this);
  if (notes === void 0) {
    notes = [];
    LAZY_NOTES.set(this, notes);
  }
  return notes;
}
function setLazyNotes(notes) {
  LAZY_NOTES.set(this, notes);
}
function lazyCharacteristics() {
  let characteristics = LAZY_CHARACTERISTICS.get(this);
  if (characteristics === void 0) {
    characteristics = [];
    LAZY_CHARACTERISTICS.set(this, characteristics);
  }
  return characteristics;
}
function setLazyCharacteristics(characteristics) {
  LAZY_CHARACTERISTICS.set(this, characteristics);
}
function withLazyStataMetadata(target) {
  Object.defineProperties(target, {
    notes: {
      configurable: true,
      enumerable: true,
      get: lazyNotes,
      set: setLazyNotes
    },
    characteristics: {
      configurable: true,
      enumerable: true,
      get: lazyCharacteristics,
      set: setLazyCharacteristics
    }
  });
  return target;
}
function noteNumber(name) {
  const match = NOTE_NAME.exec(name);
  if (match === null) return null;
  const number = Number(match[1]);
  return Number.isInteger(number) && number >= 1 && number <= 9999 && match[1] === String(number) ? number : null;
}
function reservedCharacteristicName(name) {
  return NOTE_NAME.test(name) || name === "_lang_list" || name === "_lang_c" || name === "fralias_from" || name === "fralias_varname" || name.startsWith("_lang_v_") || name.startsWith("_lang_l_");
}
function validCharacteristicNameShape(name) {
  return /^[_\p{L}][_\p{L}\p{N}]*$/u.test(name) && codePointLengthAtMost(name, 32) && utf8LengthAtMost(name, 128);
}
function mutableNotes(target) {
  const current = target.notes;
  if (current === void 0) {
    const notes = [];
    target.notes = notes;
    return notes;
  }
  if (!Array.isArray(current)) {
    throw new Error("Malformed Stata note metadata");
  }
  if (current.length > 0 && current.every((note) => typeof note === "string")) {
    if (current.length > 9999) {
      throw new Error("Malformed Stata note metadata");
    }
    const notes = current.map((text2, index) => {
      validExistingMetadataValue(text2, "note");
      return { number: index + 1, text: text2 };
    });
    target.notes = notes;
    return notes;
  }
  const numbers = /* @__PURE__ */ new Set();
  for (const note of current) {
    if (typeof note !== "object" || note === null) {
      throw new Error("Malformed Stata note metadata");
    }
    const { number, text: text2 } = note;
    if (!Number.isInteger(number) || number < 1 || number > 9999 || numbers.has(number)) {
      throw new Error("Malformed Stata note metadata");
    }
    validExistingMetadataValue(text2, "note");
    numbers.add(number);
  }
  return current;
}
function mutableCharacteristics(target) {
  if (target.characteristics === void 0) {
    target.characteristics = [];
  }
  if (!Array.isArray(target.characteristics)) {
    throw new Error("Malformed Stata characteristic metadata");
  }
  const names = /* @__PURE__ */ new Set();
  for (const characteristic of target.characteristics) {
    if (typeof characteristic !== "object" || characteristic === null) {
      throw new Error("Malformed Stata characteristic metadata");
    }
    const { name, value } = characteristic;
    if (typeof name !== "string" || !validCharacteristicNameShape(name) || reservedCharacteristicName(name) || names.has(name)) {
      throw new Error("Malformed Stata characteristic metadata");
    }
    validExistingMetadataValue(value, "characteristic");
    names.add(name);
  }
  return target.characteristics;
}
var StataMetadataCollector = class {
  dataset;
  variables;
  targetIndexes;
  uniqueNoteScopes;
  uniqueCharacteristicScopes;
  constructor(dataset, variables) {
    this.dataset = dataset;
    this.variables = variables;
  }
  /** Variable-name lookup entries still retained by this collector. */
  get retainedTargetIndexCount() {
    return this.targetIndexes?.size ?? 0;
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
  uniqueNotes(scopeIndex) {
    let scopes = this.uniqueNoteScopes;
    if (scopes === void 0) {
      scopes = new Uint8Array(this.variables.length + 1);
      this.uniqueNoteScopes = scopes;
    }
    const scope = this.scope(scopeIndex);
    if (scopes[scopeIndex] === 0) {
      const values = mutableNotes(scope);
      scopes[scopeIndex] = 1;
      return values;
    }
    return scope.notes;
  }
  uniqueCharacteristics(scopeIndex) {
    let scopes = this.uniqueCharacteristicScopes;
    if (scopes === void 0) {
      scopes = new Uint8Array(this.variables.length + 1);
      this.uniqueCharacteristicScopes = scopes;
    }
    const scope = this.scope(scopeIndex);
    if (scopes[scopeIndex] === 0) {
      const values = mutableCharacteristics(scope);
      scopes[scopeIndex] = 1;
      return values;
    }
    return scope.characteristics;
  }
  accept(target, name) {
    if (!validCharacteristicNameShape(name)) {
      throw new Error("Invalid on-disk Stata characteristic name");
    }
    const number = noteNumber(name);
    if (number === null && reservedCharacteristicName(name)) return null;
    const scopeIndex = this.targetIndex(target);
    if (scopeIndex === void 0) return null;
    return { scopeIndex, name, noteNumber: number };
  }
  /** Materialize a record from a plan that already resolved duplicates. */
  pushAcceptedUniqueLazy(accepted, value) {
    this.targetIndexes = void 0;
    const decoded = value();
    validExistingMetadataValue(
      decoded,
      accepted.noteNumber === null ? "characteristic" : "note"
    );
    if (accepted.noteNumber !== null) {
      this.uniqueNotes(accepted.scopeIndex).push({
        number: accepted.noteNumber,
        text: decoded
      });
    } else {
      this.uniqueCharacteristics(accepted.scopeIndex).push({
        name: accepted.name,
        value: decoded
      });
    }
  }
  finish() {
    const uniqueNoteScopes = this.uniqueNoteScopes;
    if (uniqueNoteScopes !== void 0) {
      for (let scopeIndex = 0; scopeIndex < uniqueNoteScopes.length; scopeIndex++) {
        if (uniqueNoteScopes[scopeIndex] !== 0) {
          this.scope(scopeIndex).notes.sort(
            (left, right) => left.number - right.number
          );
        }
      }
    }
    this.targetIndexes = void 0;
    this.uniqueNoteScopes = void 0;
    this.uniqueCharacteristicScopes = void 0;
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
  if (length > MAX_DTA_METADATA_VALUE_BYTES + 1) {
    throw new Error("Characteristic value exceeds the 67,784-byte limit");
  }
  const limit = start + length;
  let end = start;
  while (end < limit && bytes[end] !== 0) end++;
  if (end - start > MAX_DTA_METADATA_VALUE_BYTES) {
    throw new Error("Characteristic value exceeds the 67,784-byte limit");
  }
  return end;
}
function validMetadataValue(value) {
  if (typeof value !== "string" || value.includes("\0") || !utf8LengthAtMost(value, MAX_DTA_METADATA_VALUE_BYTES)) {
    throw new Error("Invalid or over-limit Stata metadata value");
  }
}
function validExistingMetadataValue(value, kind) {
  if (typeof value !== "string" || value.includes("\0") || !codePointLengthAtMost(
    value,
    MAX_DTA_METADATA_VALUE_BYTES
  ) || !utf8LengthAtMost(
    value,
    MAX_DECODED_DTA_METADATA_VALUE_BYTES
  )) {
    throw new Error(`Malformed Stata ${kind} metadata`);
  }
}
function listStataNotes(target) {
  return mutableNotes(target).map((note) => ({ ...note }));
}
function getStataNote(target, number) {
  validNoteNumber(number);
  return mutableNotes(target).find((note) => note.number === number)?.text;
}
function setStataNote(target, number, text2) {
  validNoteNumber(number);
  validMetadataValue(text2);
  const notes = mutableNotes(target);
  const existing = notes.find((note) => note.number === number);
  if (existing === void 0) notes.push({ number, text: text2 });
  else existing.text = text2;
  notes.sort((left, right) => left.number - right.number);
}
function addStataNote(target, text2) {
  const notes = mutableNotes(target);
  const number = notes.length === 0 ? 1 : Math.max(...notes.map((note) => note.number)) + 1;
  validNoteNumber(number);
  setStataNote(target, number, text2);
  return number;
}
function dropStataNotes(target, numbers) {
  mutableNotes(target);
  if (numbers === void 0) {
    target.notes = [];
    return;
  }
  numbers.forEach(validNoteNumber);
  const dropped = new Set(numbers);
  target.notes = mutableNotes(target).filter(
    (note) => !dropped.has(note.number)
  );
}
function renumberStataNotes(target, start = 1) {
  validNoteNumber(start);
  const notes = mutableNotes(target);
  if (notes.length > 0 && start + notes.length - 1 > 9999) {
    throw new Error("Renumbered notes would exceed note number 9999");
  }
  notes.sort((left, right) => left.number - right.number).forEach((note, index) => {
    note.number = start + index;
  });
}
function listStataCharacteristics(target) {
  return mutableCharacteristics(target).map(
    (characteristic) => ({ ...characteristic })
  );
}
function getStataCharacteristic(target, name) {
  validCharacteristicName(name);
  return mutableCharacteristics(target).find((item) => item.name === name)?.value;
}
function setStataCharacteristic(target, name, value) {
  validCharacteristicName(name);
  validMetadataValue(value);
  const characteristics = mutableCharacteristics(target);
  const existing = characteristics.find((item) => item.name === name);
  if (existing === void 0) characteristics.push({ name, value });
  else existing.value = value;
}
function dropStataCharacteristics(target, names) {
  mutableCharacteristics(target);
  if (names === void 0) {
    target.characteristics = [];
    return;
  }
  names.forEach(validCharacteristicName);
  const dropped = new Set(names);
  target.characteristics = mutableCharacteristics(target).filter(
    (characteristic) => !dropped.has(characteristic.name)
  );
}

// src/characteristic-payload.ts
function canonicalRecordKey(accepted) {
  const key = accepted.noteNumber === null ? `c:${accepted.name}` : `n:${accepted.noteNumber}`;
  return `${accepted.scopeIndex}\0${key}`;
}
function readFixedString(bytes, start, width, decoder2) {
  let end = start;
  const limit = start + width;
  while (end < limit && bytes[end] !== 0) end++;
  return decoder2.decode(bytes.subarray(start, end));
}
var StataCharacteristicFramePlan = class {
  constructor(bytes, decoder2, collector) {
    this.bytes = bytes;
    this.decoder = decoder2;
    this.collector = collector;
  }
  bytes;
  decoder;
  collector;
  records = [];
  recordIndices = /* @__PURE__ */ new Map();
  deferredError;
  hasDeferredError = false;
  /** Number of distinct accepted scope/key locators retained for decoding. */
  get retainedCount() {
    return this.records.length;
  }
  /** Number of canonical-key lookup entries still retained for framing. */
  get retainedIndexCount() {
    return this.recordIndices?.size ?? 0;
  }
  add(locator) {
    const recordIndices = this.recordIndices;
    if (recordIndices === void 0) {
      throw new Error("Stata characteristic frame plan is already finished");
    }
    let valueEnd;
    try {
      valueEnd = stataMetadataValueEnd(
        this.bytes,
        locator.valueStart,
        locator.valueLength
      );
    } catch (error) {
      if (!this.hasDeferredError) {
        this.deferredError = error;
        this.hasDeferredError = true;
      }
      return;
    }
    if (this.hasDeferredError) return;
    const target = readFixedString(
      this.bytes,
      locator.namesStart,
      locator.nameWidth,
      this.decoder
    );
    const name = readFixedString(
      this.bytes,
      locator.namesStart + locator.nameWidth,
      locator.nameWidth,
      this.decoder
    );
    try {
      const accepted = this.collector.accept(target, name);
      if (accepted !== null) {
        const key = canonicalRecordKey(accepted);
        const existing = recordIndices.get(key);
        if (existing === void 0) {
          recordIndices.set(key, this.records.length);
          this.records.push({
            accepted,
            valueStart: locator.valueStart,
            valueEnd
          });
        } else {
          const record = this.records[existing];
          record.valueStart = locator.valueStart;
          record.valueEnd = valueEnd;
        }
      }
    } catch (error) {
      this.deferredError = error;
      this.hasDeferredError = true;
    }
  }
  finish() {
    if (this.recordIndices === void 0) {
      throw new Error("Stata characteristic frame plan is already finished");
    }
    this.recordIndices = void 0;
    if (this.hasDeferredError) throw this.deferredError;
    for (const record of this.records) {
      this.collector.pushAcceptedUniqueLazy(record.accepted, () => {
        return this.decoder.decode(
          this.bytes.subarray(record.valueStart, record.valueEnd)
        );
      });
    }
    this.collector.finish();
  }
};

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
function read_fixed_string(bytes, offset, field_width, decoder2) {
  let my_end = offset;
  const my_limit = offset + field_width;
  while (my_end < my_limit && bytes[my_end] !== 0) {
    my_end++;
  }
  return decoder2.decode(
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
function expect_tag(bytes, offset, tag) {
  if (!tag_at(bytes, offset, tag)) {
    throw new Error(`Missing ${ASCII_DECODER.decode(tag)} tag at offset ${offset}`);
  }
  return offset + tag.length;
}
function validate_fixed_section(bytes, start, next, name, payload_length) {
  const payload = expect_tag(bytes, start, encode_tag(`<${name}>`));
  const end = expect_tag(bytes, payload + payload_length, encode_tag(`</${name}>`));
  if (end !== next) throw new Error(`Corrupt ${name} section: mapped boundary mismatch`);
}
function frame_characteristics(bytes, view, little_endian, section_offsets, field_width, plan) {
  let pos = section_offsets.characteristics;
  if (!tag_at(bytes, pos, TAG_CHARACTERISTICS_OPEN)) {
    throw new Error("Missing <characteristics> tag");
  }
  pos += TAG_CHARACTERISTICS_OPEN.length;
  const names_length = field_width * 2;
  while (pos < section_offsets.data) {
    if (tag_at(bytes, pos, TAG_CHARACTERISTICS_CLOSE)) {
      pos += TAG_CHARACTERISTICS_CLOSE.length;
      if (pos !== section_offsets.data) {
        throw new Error("Characteristics section does not end at the mapped data offset");
      }
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
    plan.add({
      namesStart: pos,
      nameWidth: field_width,
      valueStart: pos + names_length,
      valueLength: length - names_length
    });
    pos += length;
    if (!tag_at(bytes, pos, TAG_CHARACTERISTIC_CLOSE)) {
      throw new Error("Missing </ch> tag");
    }
    pos += TAG_CHARACTERISTIC_CLOSE.length;
  }
  throw new Error("Missing </characteristics> tag");
}
function parse_characteristics(bytes, view, little_endian, section_offsets, field_width, decoder2, dataset, variables) {
  const collector = new StataMetadataCollector(dataset, variables);
  const plan = new StataCharacteristicFramePlan(bytes, decoder2, collector);
  frame_characteristics(
    bytes,
    view,
    little_endian,
    section_offsets,
    field_width,
    plan
  );
  plan.finish();
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
  const my_data_start = expect_tag(bytes, start, TAG_BYTEORDER_OPEN);
  const my_close = my_data_start + 3;
  expect_tag(bytes, my_close, TAG_BYTEORDER_CLOSE);
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
  const my_data_start = expect_tag(bytes, start, TAG_K_OPEN);
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
  return { nvar: my_nvar, end: expect_tag(bytes, my_data_end, TAG_K_CLOSE) };
}
function parse_nobs(bytes, view, little_endian, format_version, start) {
  const my_data_start = expect_tag(bytes, start, TAG_N_OPEN);
  let my_nobs;
  let my_data_end;
  if (format_version === 117) {
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
  return { nobs: my_nobs, end: expect_tag(bytes, my_data_end, TAG_N_CLOSE) };
}
function parse_dataset_label(bytes, view, little_endian, format_version, start, decoder2) {
  const my_data_start = expect_tag(bytes, start, TAG_LABEL_OPEN);
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
  const my_label = decoder2.decode(
    bytes.subarray(my_str_start, my_str_start + my_str_len)
  );
  const my_close = my_str_start + my_str_len;
  expect_tag(bytes, my_close, TAG_LABEL_CLOSE);
  return {
    dataset_label: my_label,
    end: my_close + TAG_LABEL_CLOSE.length
  };
}
var SECTION_OFFSET_KEYS = [
  "dta_data",
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
  "dta_data_close",
  "end_of_file"
];
function parse_section_map(bytes, view, little_endian, start) {
  const my_open = start;
  const my_data_start = expect_tag(bytes, start, TAG_MAP_OPEN);
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
  const after_map = expect_tag(bytes, my_data_start + SECTION_MAP_ENTRIES * 8, TAG_MAP_CLOSE);
  if (my_offsets.dta_data !== 0 || my_offsets.map !== my_open || my_offsets.variable_types !== after_map) {
    throw new Error("Corrupt .dta map: section offset mismatch");
  }
  for (let i = 1; i < SECTION_MAP_ENTRIES; i++) {
    if (my_offsets[SECTION_OFFSET_KEYS[i]] <= my_offsets[SECTION_OFFSET_KEYS[i - 1]]) {
      throw new Error("Corrupt .dta map: section offsets are not increasing");
    }
  }
  return my_offsets;
}
function parse_modern_metadata_header(buffer, options = {}) {
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  const format_version = detect_format_version(bytes);
  const text_encoding = resolve_text_encoding(format_version, options.encoding);
  const decoder2 = text_decoder(text_encoding);
  const widths = FIELD_WIDTHS[format_version];
  const { byte_order, end: after_byteorder } = parse_byte_order(
    bytes,
    FORMAT_SIGNATURES[format_version].length
  );
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
    decoder2
  );
  const timestamp_start = expect_tag(bytes, after_label, encode_tag("<timestamp>"));
  const timestamp_end = timestamp_start + 1 + view.getUint8(timestamp_start);
  const after_timestamp = expect_tag(bytes, timestamp_end, TAG_TIMESTAMP_CLOSE);
  const after_header = expect_tag(bytes, after_timestamp, encode_tag("</header>"));
  const section_offsets = parse_section_map(
    bytes,
    view,
    little_endian,
    after_header
  );
  return {
    format_version,
    text_encoding,
    decoder: decoder2,
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
function parse_fixed_string_section(bytes, tag, search_start, nvar, field_width, decoder2) {
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
        decoder2
      )
    );
  }
  return the_strings;
}
function parse_metadata(buffer, options = {}) {
  return parse_metadata_from_header(
    buffer,
    parse_modern_metadata_header(buffer, options)
  );
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
  if (section_offsets.data > bytes.length) {
    throw new Error(
      "Corrupt .dta file: mapped data offset exceeds buffer length"
    );
  }
  validate_fixed_section(
    bytes,
    section_offsets.variable_types,
    section_offsets.varnames,
    "variable_types",
    nvar * 2
  );
  validate_fixed_section(
    bytes,
    section_offsets.varnames,
    section_offsets.sortlist,
    "varnames",
    nvar * my_widths.varname
  );
  validate_fixed_section(
    bytes,
    section_offsets.sortlist,
    section_offsets.formats,
    "sortlist",
    (nvar + 1) * (format_version === 119 ? 4 : 2)
  );
  validate_fixed_section(
    bytes,
    section_offsets.formats,
    section_offsets.value_label_names,
    "formats",
    nvar * my_widths.format
  );
  validate_fixed_section(
    bytes,
    section_offsets.value_label_names,
    section_offsets.variable_labels,
    "value_label_names",
    nvar * my_widths.value_label_name
  );
  validate_fixed_section(
    bytes,
    section_offsets.variable_labels,
    section_offsets.characteristics,
    "variable_labels",
    nvar * my_widths.variable_label
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
    the_variables.push(withLazyStataMetadata({
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
    }));
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

// src/arrow-checksum.ts
var MASK = 0xffffffffffffffffn;
var P1 = 11400714785074694791n;
var P2 = 14029467366897019727n;
var P3 = 1609587929392839161n;
var P4 = 9650029242287828579n;
var P5 = 2870177450012600261n;
var rotate = (value, count) => (value << count | value >> 64n - count) & MASK;
var round = (acc, value) => rotate(acc + value * P2 & MASK, 31n) * P1 & MASK;
function xxh64(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let cursor = 0;
  let hash;
  if (bytes.length >= 32) {
    let a = P1 + P2 & MASK;
    let b = P2;
    let c = 0n;
    let d = -P1 & MASK;
    do {
      a = round(a, view.getBigUint64(cursor, true));
      b = round(b, view.getBigUint64(cursor + 8, true));
      c = round(c, view.getBigUint64(cursor + 16, true));
      d = round(d, view.getBigUint64(cursor + 24, true));
      cursor += 32;
    } while (cursor <= bytes.length - 32);
    hash = rotate(a, 1n) + rotate(b, 7n) + rotate(c, 12n) + rotate(d, 18n) & MASK;
    for (const lane of [a, b, c, d]) {
      hash = (hash ^ round(0n, lane)) * P1 + P4 & MASK;
    }
  } else {
    hash = P5;
  }
  hash = hash + BigInt(bytes.length) & MASK;
  while (cursor + 8 <= bytes.length) {
    hash ^= round(0n, view.getBigUint64(cursor, true));
    hash = rotate(hash, 27n) * P1 + P4 & MASK;
    cursor += 8;
  }
  if (cursor + 4 <= bytes.length) {
    hash ^= BigInt(view.getUint32(cursor, true)) * P1 & MASK;
    hash = rotate(hash, 23n) * P2 + P3 & MASK;
    cursor += 4;
  }
  while (cursor < bytes.length) {
    hash ^= BigInt(bytes[cursor++]) * P5 & MASK;
    hash = rotate(hash, 11n) * P1 & MASK;
  }
  hash ^= hash >> 33n;
  hash = hash * P2 & MASK;
  hash ^= hash >> 29n;
  hash = hash * P3 & MASK;
  return (hash ^ hash >> 32n) & MASK;
}
function integer(value) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error("Invalid Arrow checksum offset or length");
  }
}
function slice(bytes, start, length) {
  integer(start);
  integer(length);
  if (!bytes || start > bytes.length || length > bytes.length - start) {
    throw new Error("Arrow checksum buffer is too short");
  }
  return bytes.subarray(start, start + length);
}
function bitmap(bytes, offset, length) {
  integer(offset);
  if (offset % 8 !== 0) throw new Error("Bitmap checksum requires a byte-aligned offset");
  const result = slice(bytes, offset / 8, Math.ceil(length / 8));
  if (length % 8 === 0) return result;
  const masked = result.slice();
  masked[masked.length - 1] &= (1 << length % 8) - 1;
  return masked;
}
function canonicalBufferHashes(array2) {
  integer(array2.length);
  const offset = array2.offset ?? 0;
  integer(offset);
  const result = [];
  const hash = (bytes) => {
    result.push(xxh64(bytes).toString(16).padStart(16, "0"));
  };
  if (array2.validity !== void 0) {
    hash(bitmap(array2.validity, array2.validityOffset ?? offset, array2.length));
  }
  if (array2.type === "bool") {
    hash(bitmap(slice(array2.buffers[0], 0, array2.buffers[0]?.length ?? 0), offset, array2.length));
  } else if (array2.type === "utf8" || array2.type === "large-utf8") {
    const width = array2.type === "utf8" ? 4 : 8;
    const raw = slice(array2.buffers[0], offset * width, (array2.length + 1) * width);
    const view = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
    const read = (index) => width === 4 ? BigInt(view.getInt32(index * width, true)) : view.getBigInt64(index * width, true);
    const first = read(0);
    let previous = first;
    const rebased = new Uint8Array(raw.length);
    const output = new DataView(rebased.buffer);
    for (let index = 0; index <= array2.length; index++) {
      const value = read(index);
      if (value < 0n || value < previous || value > BigInt(Number.MAX_SAFE_INTEGER)) {
        throw new Error("Invalid Arrow string checksum offsets");
      }
      const relative = value - first;
      if (width === 4) output.setInt32(index * width, Number(relative), true);
      else output.setBigInt64(index * width, relative, true);
      previous = value;
    }
    hash(first === 0n ? raw : rebased);
    hash(slice(array2.buffers[1], Number(first), Number(previous - first)));
  } else {
    const widths = {
      int8: 1,
      uint8: 1,
      int16: 2,
      uint16: 2,
      int32: 4,
      uint32: 4,
      float32: 4,
      date32: 4,
      int64: 8,
      uint64: 8,
      float64: 8,
      date64: 8,
      timestamp: 8,
      duration: 8
    };
    const type = array2.type === "dictionary" ? array2.dictionaryKeyType ?? "" : array2.type;
    const width = Object.hasOwn(widths, type) ? widths[type] : void 0;
    if (!width) throw new Error(`Cannot checksum unsupported Arrow type ${array2.type}`);
    hash(slice(array2.buffers[0], offset * width, array2.length * width));
  }
  return result;
}

// src/arrow-flatbuffer.ts
var FlatBuffer = class {
  constructor(bytes) {
    this.bytes = bytes;
    this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  }
  bytes;
  view;
  decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
  range(position, length) {
    if (!Number.isSafeInteger(position) || !Number.isSafeInteger(length) || position < 0 || length < 0 || position > this.bytes.length - length) {
      throw new Error("Invalid Arrow IPC metadata: offset outside buffer");
    }
    return position;
  }
  u8(p) {
    return this.view.getUint8(this.range(p, 1));
  }
  i16(p) {
    return this.view.getInt16(this.range(p, 2), true);
  }
  u16(p) {
    return this.view.getUint16(this.range(p, 2), true);
  }
  i32(p) {
    return this.view.getInt32(this.range(p, 4), true);
  }
  u32(p) {
    return this.view.getUint32(this.range(p, 4), true);
  }
  i64(p) {
    return this.view.getBigInt64(this.range(p, 8), true);
  }
  size(p) {
    const value = this.i64(p);
    if (value < 0n || value > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new Error("Invalid Arrow IPC metadata: size is not a safe integer");
    }
    return Number(value);
  }
  indirect(p) {
    const offset = this.u32(p);
    if (offset < 4) throw new Error("Invalid Arrow IPC metadata: invalid relative offset");
    return this.range(p + offset, 4);
  }
  root() {
    return this.indirect(0);
  }
  field(table, index, width = 4) {
    const vtable = table - this.i32(table);
    const length = this.u16(vtable);
    const objectLength = this.u16(vtable + 2);
    if (length < 4 || length % 2 || objectLength < 4) {
      throw new Error("Invalid Arrow IPC metadata: invalid table length");
    }
    this.range(vtable, length);
    this.range(table, objectLength);
    if (4 + index * 2 >= length) return void 0;
    const offset = this.u16(vtable + 4 + index * 2);
    if (!offset) return void 0;
    if (offset < 4 || offset + width > objectLength) {
      throw new Error("Invalid Arrow IPC metadata: field outside table");
    }
    return table + offset;
  }
  scalar(table, index, kind, fallback = 0) {
    const position = this.field(table, index, kind === "u8" ? 1 : kind === "i16" ? 2 : 4);
    return position === void 0 ? fallback : this[kind](position);
  }
  boolean(table, index) {
    const value = this.scalar(table, index, "u8");
    if (value > 1) throw new Error("Invalid Arrow IPC metadata: invalid boolean");
    return value === 1;
  }
  child(table, index, required = false) {
    const position = this.field(table, index);
    if (position !== void 0) return this.indirect(position);
    if (required) throw new Error("Invalid Arrow IPC metadata: missing required table");
    return void 0;
  }
  vector(table, index, width) {
    const position = this.child(table, index);
    if (position === void 0) return { start: 0, length: 0 };
    const length = this.u32(position);
    const start = position + 4;
    this.range(start, length * width);
    return { start, length };
  }
  tables(table, index) {
    const { start, length } = this.vector(table, index, 4);
    return Array.from({ length }, (_, i) => this.indirect(start + 4 * i));
  }
  string(table, index, required = false) {
    const position = this.child(table, index, required);
    if (position === void 0) return void 0;
    const length = this.u32(position);
    this.range(position + 4, length + 1);
    if (this.u8(position + 4 + length) !== 0) {
      throw new Error("Invalid Arrow IPC metadata: unterminated string");
    }
    return this.decoder.decode(this.bytes.subarray(position + 4, position + 4 + length));
  }
  metadata(table, index) {
    const result = /* @__PURE__ */ new Map();
    for (const entry of this.tables(table, index)) {
      const key = this.string(entry, 0, true);
      const value = this.string(entry, 1) ?? "";
      if (result.has(key)) throw new Error(`Invalid Arrow IPC metadata: duplicate key ${key}`);
      result.set(key, value);
    }
    return result;
  }
};

// src/vendor/fzstd.ts
var ab = ArrayBuffer;
var u8 = Uint8Array;
var u16 = Uint16Array;
var i16 = Int16Array;
var i32 = Int32Array;
var slc = (v, s, e) => {
  if (u8.prototype.slice) return u8.prototype.slice.call(v, s, e);
  if (s == null || s < 0) s = 0;
  if (e == null || e > v.length) e = v.length;
  const n = new u8(e - s);
  n.set(v.subarray(s, e));
  return n;
};
var fill = (v, n, s, e) => {
  if (u8.prototype.fill) return u8.prototype.fill.call(v, n, s, e);
  if (s == null || s < 0) s = 0;
  if (e == null || e > v.length) e = v.length;
  for (; s < e; ++s) v[s] = n;
  return v;
};
var ec = [
  "invalid zstd data",
  "window size too large (>2046MB)",
  "invalid block type",
  "FSE accuracy too high",
  "match distance too far back",
  "unexpected EOF"
];
var err = (ind, msg, nt) => {
  const e = new Error(msg || ec[ind]);
  e.code = ind;
  if (Error.captureStackTrace) Error.captureStackTrace(e, err);
  if (!nt) throw e;
  return e;
};
var rb = (d, b, n) => {
  let i = 0, o = 0;
  for (; i < n; ++i) o += d[b++] * 2 ** (i * 8);
  if (!Number.isSafeInteger(o)) err(0);
  return o;
};
var b4 = (d, b) => (d[b] | d[b + 1] << 8 | d[b + 2] << 16 | d[b + 3] << 24) >>> 0;
var rzfh = (dat, w) => {
  if (dat.length < 5) err(5);
  const n3 = dat[0] | dat[1] << 8 | dat[2] << 16;
  if (n3 == 3126568 && dat[3] == 253) {
    const flg = dat[4];
    const ss = flg >> 5 & 1, cc = flg >> 2 & 1, df = flg & 3, fcf = flg >> 6;
    if (flg & 24) err(0);
    let bt = 6 - ss;
    const db = df == 3 ? 4 : df;
    if (bt + db > dat.length) err(5);
    const di = rb(dat, bt, db);
    bt += db;
    const fsb = fcf ? 1 << fcf : ss;
    if (bt + fsb > dat.length) err(5);
    const fss = rb(dat, bt, fsb) + (fcf == 1 && 256);
    let ws = fss;
    if (!ss) {
      const wb = 2 ** (10 + (dat[5] >> 3));
      ws = wb + wb / 8 * (dat[5] & 7);
    }
    return {
      b: bt + fsb,
      y: 0,
      l: 0,
      d: di,
      w,
      e: ws,
      o: [1, 4, 8],
      u: fss,
      f: fsb !== 0,
      x: ws,
      c: cc,
      m: Math.min(131072, ws)
    };
  } else if ((n3 >> 4 | dat[3] << 20) == 25481893) {
    return b4(dat, 4) + 8;
  }
  err(0);
};
var msb = (val) => {
  let bits = 0;
  for (; 1 << bits <= val; ++bits) ;
  return bits - 1;
};
var rfse = (dat, bt, mal) => {
  let tpos = (bt << 3) + 4;
  const al = (dat[bt] & 15) + 5;
  if (al > mal) err(3);
  const sz = 1 << al;
  let probs = sz, sym = -1, re = -1, i = -1, ht = sz;
  const buf = new ab(512 + (sz << 2));
  const freq = new i16(buf, 0, 256);
  const dstate = new u16(buf, 0, 256);
  const nstate = new u16(buf, 512, sz);
  const bb1 = 512 + (sz << 1);
  const syms = new u8(buf, bb1, sz);
  const nbits = new u8(buf, bb1 + sz);
  while (sym < 255 && probs > 0) {
    const bits = msb(probs + 1);
    const cbt = tpos >> 3;
    const msk = (1 << bits + 1) - 1;
    let val = (dat[cbt] | dat[cbt + 1] << 8 | dat[cbt + 2] << 16) >> (tpos & 7) & msk;
    const msk1fb = (1 << bits) - 1;
    const msv = msk - probs - 1;
    const sval = val & msk1fb;
    if (sval < msv) tpos += bits, val = sval;
    else {
      tpos += bits + 1;
      if (val > msk1fb) val -= msv;
    }
    freq[++sym] = --val;
    if (val == -1) {
      probs += val;
      syms[--ht] = sym;
    } else probs -= val;
    if (!val) {
      do {
        const rbt = tpos >> 3;
        re = (dat[rbt] | dat[rbt + 1] << 8) >> (tpos & 7) & 3;
        tpos += 2;
        sym += re;
      } while (re == 3 && sym < 255 && tpos <= dat.length * 8);
    }
  }
  if (sym > 255 || probs) err(0);
  let sympos = 0;
  const sstep = (sz >> 1) + (sz >> 3) + 3;
  const smask = sz - 1;
  for (let s = 0; s <= sym; ++s) {
    const sf = freq[s];
    if (sf < 1) {
      dstate[s] = -sf;
      continue;
    }
    for (i = 0; i < sf; ++i) {
      syms[sympos] = s;
      do {
        sympos = sympos + sstep & smask;
      } while (sympos >= ht);
    }
  }
  if (sympos) err(0);
  for (i = 0; i < sz; ++i) {
    const ns = dstate[syms[i]]++;
    const nb = nbits[i] = al - msb(ns);
    nstate[i] = (ns << nb) - sz;
  }
  return [tpos + 7 >> 3, {
    b: al,
    s: syms,
    n: nbits,
    t: nstate
  }];
};
var rhu = (dat, bt) => {
  let i = 0, wc = -1;
  const buf = new u8(292), hb = dat[bt];
  const hw = buf.subarray(0, 256);
  const rc = buf.subarray(256, 268);
  const ri = new u16(buf.buffer, 268);
  if (hb < 128) {
    const [ebt, fdt] = rfse(dat, bt + 1, 6);
    bt += hb;
    const epos = ebt << 3;
    const lb = dat[bt];
    if (!lb) err(0);
    let st1 = 0, st2 = 0, btr1 = fdt.b, btr2 = btr1;
    let fpos = (++bt << 3) - 8 + msb(lb);
    for (; ; ) {
      fpos -= btr1;
      if (fpos < epos) break;
      let cbt = fpos >> 3;
      st1 += (dat[cbt] | dat[cbt + 1] << 8) >> (fpos & 7) & (1 << btr1) - 1;
      hw[++wc] = fdt.s[st1];
      fpos -= btr2;
      if (fpos < epos) break;
      cbt = fpos >> 3;
      st2 += (dat[cbt] | dat[cbt + 1] << 8) >> (fpos & 7) & (1 << btr2) - 1;
      hw[++wc] = fdt.s[st2];
      btr1 = fdt.n[st1];
      st1 = fdt.t[st1];
      btr2 = fdt.n[st2];
      st2 = fdt.t[st2];
    }
    if (++wc > 255) err(0);
  } else {
    wc = hb - 127;
    for (; i < wc; i += 2) {
      const byte = dat[++bt];
      hw[i] = byte >> 4;
      hw[i + 1] = byte & 15;
    }
    ++bt;
  }
  let wes = 0;
  for (i = 0; i < wc; ++i) {
    const wt = hw[i];
    if (wt > 11) err(0);
    wes += wt && 1 << wt - 1;
  }
  const mb = msb(wes) + 1;
  const ts = 1 << mb;
  const rem = ts - wes;
  if (rem & rem - 1) err(0);
  hw[wc++] = msb(rem) + 1;
  for (i = 0; i < wc; ++i) {
    const wt = hw[i];
    ++rc[hw[i] = wt && mb + 1 - wt];
  }
  const hbuf = new u8(ts << 1);
  const syms = hbuf.subarray(0, ts), nb = hbuf.subarray(ts);
  ri[mb] = 0;
  for (i = mb; i > 0; --i) {
    const pv = ri[i];
    fill(nb, i, pv, ri[i - 1] = pv + rc[i] * (1 << mb - i));
  }
  if (ri[0] != ts) err(0);
  for (i = 0; i < wc; ++i) {
    const bits = hw[i];
    if (bits) {
      const code = ri[bits];
      fill(syms, i, code, ri[bits] = code + (1 << mb - bits));
    }
  }
  return [bt, {
    n: nb,
    b: mb,
    s: syms
  }];
};
var dllt = rfse(/* @__PURE__ */ new u8([
  81,
  16,
  99,
  140,
  49,
  198,
  24,
  99,
  12,
  33,
  196,
  24,
  99,
  102,
  102,
  134,
  70,
  146,
  4
]), 0, 6)[1];
var dmlt = rfse(/* @__PURE__ */ new u8([
  33,
  20,
  196,
  24,
  99,
  140,
  33,
  132,
  16,
  66,
  8,
  33,
  132,
  16,
  66,
  8,
  33,
  68,
  68,
  68,
  68,
  68,
  68,
  68,
  68,
  36,
  9
]), 0, 6)[1];
var doct = rfse(/* @__PURE__ */ new u8([
  32,
  132,
  16,
  66,
  102,
  70,
  68,
  68,
  68,
  68,
  36,
  73,
  2
]), 0, 5)[1];
var b2bl = (b, s) => {
  const len = b.length, bl = new i32(len);
  for (let i = 0; i < len; ++i) {
    bl[i] = s;
    s += 1 << b[i];
  }
  return bl;
};
var llb = /* @__PURE__ */ new u8((/* @__PURE__ */ new i32([
  0,
  0,
  0,
  0,
  16843009,
  50528770,
  134678020,
  202050057,
  269422093
])).buffer, 0, 36);
var llbl = /* @__PURE__ */ b2bl(llb, 0);
var mlb = /* @__PURE__ */ new u8((/* @__PURE__ */ new i32([
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  16843009,
  50528770,
  117769220,
  185207048,
  252579084,
  16
])).buffer, 0, 53);
var mlbl = /* @__PURE__ */ b2bl(mlb, 3);
var dhu = (dat, out, hu) => {
  const len = dat.length, ss = out.length, lb = dat[len - 1], msk = (1 << hu.b) - 1, eb = -hu.b;
  if (!lb) err(0);
  let st = 0, btr = hu.b, pos = (len << 3) - 8 + msb(lb) - btr, i = -1;
  for (; pos > eb && i < ss; ) {
    const cbt = pos >> 3;
    const val = (dat[cbt] | dat[cbt + 1] << 8 | dat[cbt + 2] << 16) >> (pos & 7);
    st = (st << btr | val) & msk;
    out[++i] = hu.s[st];
    pos -= btr = hu.n[st];
  }
  if (pos != eb || i + 1 != ss) err(0);
};
var dhu4 = (dat, out, hu) => {
  let bt = 6;
  const ss = out.length, sz1 = ss + 3 >> 2, sz2 = sz1 << 1, sz3 = sz1 + sz2;
  dhu(dat.subarray(bt, bt += dat[0] | dat[1] << 8), out.subarray(0, sz1), hu);
  dhu(dat.subarray(bt, bt += dat[2] | dat[3] << 8), out.subarray(sz1, sz2), hu);
  dhu(dat.subarray(bt, bt += dat[4] | dat[5] << 8), out.subarray(sz2, sz3), hu);
  dhu(dat.subarray(bt), out.subarray(sz3), hu);
};
var rzb = (dat, st, out) => {
  let bt = st.b;
  const b0 = dat[bt], btype = b0 >> 1 & 3;
  st.l = b0 & 1;
  const sz = b0 >> 3 | dat[bt + 1] << 5 | dat[bt + 2] << 13;
  const ebt = (bt += 3) + sz;
  if (sz > st.m) err(0);
  if (btype < 2 && out && st.y + sz > out.length) err(0, "Zstandard output exceeds declared Arrow buffer length");
  if (btype == 1) {
    if (bt >= dat.length) return;
    st.b = bt + 1;
    if (out) {
      fill(out, dat[bt], st.y, st.y += sz);
      return out;
    }
    return fill(new u8(sz), dat[bt]);
  }
  if (ebt > dat.length) return;
  if (btype == 0) {
    st.b = ebt;
    if (out) {
      out.set(dat.subarray(bt, ebt), st.y);
      st.y += sz;
      return out;
    }
    return slc(dat, bt, ebt);
  }
  if (btype == 2) {
    const b3 = dat[bt], lbt = b3 & 3, sf = b3 >> 2 & 3;
    let lss = b3 >> 4, lcs = 0, s4 = 0;
    if (lbt < 2) {
      if (sf & 1) lss |= dat[++bt] << 4 | (sf & 2 && dat[++bt] << 12);
      else lss = b3 >> 3;
    } else {
      s4 = sf;
      if (sf < 2) lss |= (dat[++bt] & 63) << 4, lcs = dat[bt] >> 6 | dat[++bt] << 2;
      else if (sf == 2) lss |= dat[++bt] << 4 | (dat[++bt] & 3) << 12, lcs = dat[bt] >> 2 | dat[++bt] << 6;
      else lss |= dat[++bt] << 4 | (dat[++bt] & 63) << 12, lcs = dat[bt] >> 6 | dat[++bt] << 2 | dat[++bt] << 10;
    }
    ++bt;
    let buf = out ? out.subarray(st.y, st.y + st.m) : new u8(st.m);
    let spl = buf.length - lss;
    if (spl < 0 || bt > ebt || lss > st.m) err(0);
    if (lbt == 0) buf.set(dat.subarray(bt, bt += lss), spl);
    else if (lbt == 1) fill(buf, dat[bt++], spl);
    else {
      let hu = st.h;
      if (lbt == 2) {
        const hud = rhu(dat, bt);
        lcs += bt - (bt = hud[0]);
        st.h = hu = hud[1];
      } else if (!hu) err(0);
      (s4 ? dhu4 : dhu)(dat.subarray(bt, bt += lcs), buf.subarray(spl), hu);
    }
    let ns = dat[bt++];
    if (ns) {
      if (ns == 255) ns = (dat[bt++] | dat[bt++] << 8) + 32512;
      else if (ns > 127) ns = ns - 128 << 8 | dat[bt++];
      const scm = dat[bt++];
      if (scm & 3) err(0);
      const dts = [dmlt, doct, dllt];
      for (let i = 2; i > -1; --i) {
        const md = scm >> (i << 1) + 2 & 3;
        if (md == 1) {
          const rbuf = new u8([0, 0, dat[bt++]]);
          dts[i] = {
            s: rbuf.subarray(2, 3),
            n: rbuf.subarray(0, 1),
            t: new u16(rbuf.buffer, 0, 1),
            b: 0
          };
        } else if (md == 2) {
          [bt, dts[i]] = rfse(dat, bt, 9 - (i & 1));
        } else if (md == 3) {
          if (!st.t) err(0);
          dts[i] = st.t[i];
        }
      }
      const [mlt, oct, llt] = st.t = dts;
      const lb = dat[ebt - 1];
      if (!lb) err(0);
      let spos = (ebt << 3) - 8 + msb(lb) - llt.b, cbt = spos >> 3, oubt = 0;
      let lst = (dat[cbt] | dat[cbt + 1] << 8) >> (spos & 7) & (1 << llt.b) - 1;
      cbt = (spos -= oct.b) >> 3;
      let ost = (dat[cbt] | dat[cbt + 1] << 8) >> (spos & 7) & (1 << oct.b) - 1;
      cbt = (spos -= mlt.b) >> 3;
      let mst = (dat[cbt] | dat[cbt + 1] << 8) >> (spos & 7) & (1 << mlt.b) - 1;
      for (++ns; --ns; ) {
        const llc = llt.s[lst];
        const lbtr = llt.n[lst];
        const mlc = mlt.s[mst];
        const mbtr = mlt.n[mst];
        const ofc = oct.s[ost];
        const obtr = oct.n[ost];
        cbt = (spos -= ofc) >> 3;
        if (ofc > 31 || spos < 0) err(0);
        const ofp = 2 ** ofc;
        const packed = (dat[cbt] || 0) + (dat[cbt + 1] || 0) * 256 + (dat[cbt + 2] || 0) * 65536 + (dat[cbt + 3] || 0) * 16777216 + (dat[cbt + 4] || 0) * 4294967296;
        let off = ofp + Math.floor(packed / 2 ** (spos & 7)) % ofp;
        cbt = (spos -= mlb[mlc]) >> 3;
        let ml = mlbl[mlc] + ((dat[cbt] | dat[cbt + 1] << 8 | dat[cbt + 2] << 16) >> (spos & 7) & (1 << mlb[mlc]) - 1);
        cbt = (spos -= llb[llc]) >> 3;
        const ll = llbl[llc] + ((dat[cbt] | dat[cbt + 1] << 8 | dat[cbt + 2] << 16) >> (spos & 7) & (1 << llb[llc]) - 1);
        cbt = (spos -= lbtr) >> 3;
        lst = llt.t[lst] + ((dat[cbt] | dat[cbt + 1] << 8) >> (spos & 7) & (1 << lbtr) - 1);
        cbt = (spos -= mbtr) >> 3;
        mst = mlt.t[mst] + ((dat[cbt] | dat[cbt + 1] << 8) >> (spos & 7) & (1 << mbtr) - 1);
        cbt = (spos -= obtr) >> 3;
        ost = oct.t[ost] + ((dat[cbt] | dat[cbt + 1] << 8) >> (spos & 7) & (1 << obtr) - 1);
        if (off > 3) {
          st.o[2] = st.o[1];
          st.o[1] = st.o[0];
          st.o[0] = off -= 3;
        } else {
          const idx = off - (ll != 0);
          if (idx) {
            off = idx == 3 ? st.o[0] - 1 : st.o[idx];
            if (idx > 1) st.o[2] = st.o[1];
            st.o[1] = st.o[0];
            st.o[0] = off;
          } else off = st.o[0];
        }
        if (!Number.isFinite(ll + ml) || ll > buf.length - spl || oubt + ll + ml > buf.length || off <= 0 || off > st.e + oubt + ll || off > st.x) err(0);
        for (let i = 0; i < ll; ++i) {
          buf[oubt + i] = buf[spl + i];
        }
        oubt += ll, spl += ll;
        let stin = oubt - off;
        if (stin < 0) {
          let len = -stin;
          const bs = st.e + stin;
          if (len > ml) len = ml;
          for (let i = 0; i < len; ++i) {
            buf[oubt + i] = st.w[bs + i];
          }
          oubt += len, ml -= len, stin = 0;
        }
        for (let i = 0; i < ml; ++i) {
          buf[oubt + i] = buf[stin + i];
        }
        oubt += ml;
      }
      if (oubt != spl) {
        while (spl < buf.length) {
          buf[oubt++] = buf[spl++];
        }
      } else oubt = buf.length;
      if (out) st.y += oubt;
      else buf = slc(buf, 0, oubt);
    } else if (out) {
      st.y += lss;
      if (spl) {
        for (let i = 0; i < lss; ++i) {
          buf[i] = buf[spl + i];
        }
      }
    } else if (spl) buf = slc(buf, spl);
    if (bt > ebt) err(0);
    st.b = ebt;
    return buf;
  }
  err(2);
};
function decompressFrame(dat, out) {
  const st = rzfh(dat, out);
  if (typeof st !== "object") err(0);
  if (st.d) err(0, "Zstandard external dictionaries are unsupported");
  if (st.u > out.length) err(0, "Zstandard output exceeds declared Arrow buffer length");
  st.e = 0;
  while (!st.l) {
    if (st.b + 3 > dat.length) err(5);
    if (!rzb(dat, st, out)) err(5);
    st.e = st.y;
  }
  if (st.f && st.u !== st.y) err(0, "Zstandard frame content size mismatch");
  if (st.b + st.c * 4 > dat.length) err(5);
  return { written: st.y, consumed: st.b + st.c * 4, checksumOffset: st.c ? st.b : void 0 };
}

// src/arrow-codecs.ts
var u32 = (data, offset) => new DataView(data.buffer, data.byteOffset, data.byteLength).getUint32(offset, true);
var rotl = (n, count) => n << count | n >>> 32 - count;
function xxh32(data) {
  const p1 = 2654435761, p2 = 2246822519, p3 = 3266489917, p4 = 668265263, p5 = 374761393;
  const round2 = (v, n) => Math.imul(rotl(v + Math.imul(n, p2), 13), p1);
  let at = 0, h;
  if (data.length >= 16) {
    let a = p1 + p2, b = p2, c = 0, d = -p1;
    while (at <= data.length - 16) {
      a = round2(a, u32(data, at));
      b = round2(b, u32(data, at + 4));
      c = round2(c, u32(data, at + 8));
      d = round2(d, u32(data, at + 12));
      at += 16;
    }
    h = rotl(a, 1) + rotl(b, 7) + rotl(c, 12) + rotl(d, 18);
  } else h = p5;
  h += data.length;
  while (at + 4 <= data.length) {
    h = Math.imul(rotl(h + Math.imul(u32(data, at), p3), 17), p4);
    at += 4;
  }
  while (at < data.length) h = Math.imul(rotl(h + Math.imul(data[at++], p5), 11), p1);
  h ^= h >>> 15;
  h = Math.imul(h, p2);
  h ^= h >>> 13;
  h = Math.imul(h, p3);
  h ^= h >>> 16;
  return h >>> 0;
}
function fail(message) {
  throw new Error(`Invalid Arrow compressed buffer: ${message}`);
}
function lz4(data, out) {
  let at = 0, written = 0;
  const need = (count) => {
    if (count > data.length - at) fail("truncated LZ4 frame");
  };
  while (at < data.length) {
    need(4);
    const magic = u32(data, at);
    at += 4;
    if (magic >>> 4 === 25481893) {
      need(4);
      const size = u32(data, at);
      at += 4;
      need(size);
      at += size;
      continue;
    }
    if (magic !== 407708164) fail("LZ4 frame magic");
    need(3);
    const header = at, flags = data[at++], descriptor = data[at++];
    if (flags >>> 6 !== 1 || flags & 2 || descriptor & 143) fail("LZ4 frame flags");
    const blockCode = descriptor >>> 4 & 7;
    if (blockCode < 4 || blockCode > 7) fail("LZ4 maximum block size");
    const blockMax = 2 ** (8 + blockCode * 2), frameStart = written;
    let contentSize;
    if (flags & 8) {
      need(8);
      contentSize = new DataView(data.buffer, data.byteOffset + at, 8).getBigUint64(0, true);
      at += 8;
      if (contentSize > BigInt(out.length - written)) fail("LZ4 content exceeds declared Arrow buffer length");
    }
    if (flags & 1) {
      need(4);
      if (u32(data, at) !== 0) fail("LZ4 external dictionary is unsupported");
      at += 4;
    }
    need(1);
    if ((xxh32(data.subarray(header, at)) >>> 8 & 255) !== data[at++]) fail("LZ4 header checksum mismatch");
    for (; ; ) {
      need(4);
      const block = u32(data, at);
      at += 4;
      if (block === 0) break;
      const length = block & 2147483647;
      if (!length || length > blockMax) fail("LZ4 block size");
      need(length);
      const end = at + length, blockStart = at, outputStart = written;
      if (block >>> 31) {
        if (length > out.length - written) fail("LZ4 output exceeds declared Arrow buffer length");
        out.set(data.subarray(at, end), written);
        written += length;
        at = end;
      } else {
        const extension = (base) => {
          if (base !== 15) return base;
          let n;
          do {
            if (at >= end) fail("truncated LZ4 length");
            n = data[at++];
            base += n;
          } while (n === 255);
          return base;
        };
        while (at < end) {
          const token = data[at++], literals = extension(token >>> 4);
          if (literals > end - at || literals > out.length - written) fail("LZ4 literal length");
          out.set(data.subarray(at, at + literals), written);
          at += literals;
          written += literals;
          if (at === end) break;
          if (end - at < 2) fail("truncated LZ4 match offset");
          const offset = data[at] + data[at + 1] * 256;
          at += 2;
          const match = extension(token & 15) + 4;
          if (!offset || offset > written - (flags & 32 ? outputStart : frameStart)) fail("LZ4 match offset");
          if (match > out.length - written) fail("LZ4 output exceeds declared Arrow buffer length");
          for (let i = 0; i < match; i++) {
            out[written] = out[written - offset];
            written++;
          }
        }
      }
      if (written - outputStart > blockMax) fail("LZ4 decoded block exceeds maximum size");
      if (flags & 16) {
        need(4);
        if (u32(data, at) !== xxh32(data.subarray(blockStart, end))) fail("LZ4 block checksum mismatch");
        at += 4;
      }
    }
    if (contentSize !== void 0 && contentSize !== BigInt(written - frameStart)) fail("LZ4 content size mismatch");
    if (flags & 4) {
      need(4);
      if (u32(data, at) !== xxh32(out.subarray(frameStart, written))) fail("LZ4 content checksum mismatch");
      at += 4;
    }
  }
  if (written !== out.length) fail("LZ4 output length mismatch");
}
function decodeArrowBuffer(codec, input, expectedLength) {
  if (!Number.isSafeInteger(expectedLength) || expectedLength < 0) fail("invalid decompressed length");
  const output = new Uint8Array(expectedLength);
  if (!input.length) fail("missing compression frame");
  if (codec === 0) {
    lz4(input, output);
    return output;
  }
  if (codec !== 1) fail("unsupported compression codec");
  let at = 0, written = 0;
  while (at < input.length) {
    if (input.length - at < 4) fail("truncated Zstandard frame");
    if (u32(input, at) >>> 4 === 25481893) {
      if (input.length - at < 8) fail("truncated Zstandard skippable frame");
      const size = u32(input, at + 4);
      if (size > input.length - at - 8) fail("truncated Zstandard skippable frame");
      at += size + 8;
      continue;
    }
    const frame = decompressFrame(input.subarray(at), output.subarray(written));
    if (frame.checksumOffset !== void 0 && Number(xxh64(output.subarray(written, written + frame.written)) & 0xffffffffn) !== u32(input, at + frame.checksumOffset)) fail("Zstandard content checksum mismatch");
    written += frame.written;
    at += frame.consumed;
  }
  if (written !== expectedLength) fail("Zstandard output length mismatch");
  return output;
}

// src/arrow-ipc.ts
var MAX_METADATA = 64 * 1024 * 1024;
var decoder = new TextDecoder();
function safeSize(value, name) {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error(`${name} must be a non-negative safe integer`);
  return value;
}
function intType(fb, table) {
  const width = fb.scalar(table, 0, "i32");
  if (![8, 16, 32, 64].includes(width)) throw new Error("Unsupported Arrow integer width");
  return `${fb.boolean(table, 1) ? "" : "u"}int${width}`;
}
function parseField(fb, table, bufferIndex) {
  const name = fb.string(table, 0, true);
  const kind = fb.scalar(table, 2, "u8");
  const detail = fb.child(table, 3, true);
  let type;
  let unit;
  let timezone;
  switch (kind) {
    case 2:
      type = intType(fb, detail);
      break;
    case 3: {
      const precision = fb.scalar(detail, 0, "i16");
      if (precision !== 1 && precision !== 2) throw new Error("Unsupported Arrow float precision");
      type = precision === 1 ? "float32" : "float64";
      break;
    }
    case 5:
      type = "utf8";
      break;
    case 6:
      type = "bool";
      break;
    case 8:
      if (fb.scalar(detail, 0, "i16", 1) !== 0) throw new Error("Unsupported Arrow date unit");
      type = "date32";
      unit = "day";
      break;
    case 10:
    case 18: {
      const timeUnit = fb.scalar(detail, 0, "i16", kind === 18 ? 1 : 0);
      if (timeUnit < 0 || timeUnit > 3) throw new Error("Unsupported Arrow time unit");
      unit = ["second", "millisecond", "microsecond", "nanosecond"][timeUnit];
      type = kind === 10 ? "timestamp" : "duration";
      if (kind === 10) timezone = fb.string(detail, 1);
      break;
    }
    case 20:
      type = "large-utf8";
      break;
    default:
      throw new Error(`Unsupported Arrow field type ${kind} on ${name}`);
  }
  if (fb.tables(table, 5).length) throw new Error("Unsupported Arrow nested field");
  const field = {
    name,
    type,
    nullable: fb.boolean(table, 1),
    unit,
    timezone,
    custom_metadata: fb.metadata(table, 6),
    bufferIndex
  };
  const dictionary = fb.child(table, 4);
  if (dictionary !== void 0) {
    if (type !== "utf8" && type !== "large-utf8") throw new Error("Unsupported Arrow dictionary value type");
    const indexType = fb.child(dictionary, 1);
    const key = indexType === void 0 ? "int32" : intType(fb, indexType);
    if (!["int8", "int16", "int32", "int64"].includes(key)) throw new Error("Unsupported Arrow dictionary key type");
    if (fb.scalar(dictionary, 3, "i16") !== 0) throw new Error("Unsupported Arrow dictionary kind");
    const id = fb.field(dictionary, 0, 8);
    field.dictionaryId = id === void 0 ? 0n : fb.i64(id);
    field.dictionaryKeyType = key;
    field.dictionaryValueType = type;
    field.dictionaryOrdered = fb.boolean(dictionary, 2);
    field.type = "dictionary";
  }
  return field;
}
function bufferCount(field) {
  return field.type === "utf8" || field.type === "large-utf8" ? 3 : 2;
}
function physicalWidth(type) {
  if (type === "date32") return 4;
  if (type === "timestamp" || type === "duration") return 8;
  const match = /^(?:u?int|float)(8|16|32|64)$/.exec(type);
  if (!match) throw new Error(`Arrow type ${type} has no fixed byte width`);
  return Number(match[1]) / 8;
}
function readBatch(source, block, dictionary) {
  const raw = new FlatBuffer(source.read(block.offset, block.metadataLength));
  const continuation = raw.u32(0) === 4294967295;
  const prefix = continuation ? 8 : 4;
  const length = raw.i32(continuation ? 4 : 0);
  if (length <= 0 || length > block.metadataLength - prefix) throw new Error("Invalid Arrow message length");
  const fb = new FlatBuffer(raw.bytes.subarray(prefix, prefix + length));
  const message = fb.root();
  const version2 = fb.scalar(message, 0, "i16");
  if (version2 !== 3 && version2 !== 4) throw new Error("Unsupported Arrow IPC metadata version");
  if (fb.scalar(message, 1, "u8") !== (dictionary ? 2 : 3)) throw new Error("Invalid Arrow block message type");
  const bodyLength = fb.field(message, 3, 8);
  if ((bodyLength === void 0 ? 0 : fb.size(bodyLength)) !== block.bodyLength) throw new Error("Invalid Arrow body length");
  let table = fb.child(message, 2, true);
  let dictionaryId;
  let delta;
  if (dictionary) {
    const id = fb.field(table, 0, 8);
    dictionaryId = id === void 0 ? 0n : fb.i64(id);
    delta = fb.boolean(table, 2);
    table = fb.child(table, 1, true);
  }
  const rowsPosition = fb.field(table, 0, 8);
  const rows = rowsPosition === void 0 ? 0 : fb.size(rowsPosition);
  const nodesVector = fb.vector(table, 1, 16);
  const nodes = Array.from({ length: nodesVector.length }, (_, i) => {
    const p = nodesVector.start + 16 * i;
    const length2 = fb.size(p), nullCount = fb.size(p + 8);
    if (length2 !== rows || nullCount > length2) throw new Error("Invalid Arrow field node length or null count");
    return { length: length2, nullCount };
  });
  const buffersVector = fb.vector(table, 2, 16);
  let previousEnd = 0;
  const buffers = Array.from({ length: buffersVector.length }, (_, i) => {
    const p = buffersVector.start + 16 * i;
    const offset = fb.size(p), length2 = fb.size(p + 8);
    if (offset < previousEnd || offset > block.bodyLength - length2) throw new Error("Invalid Arrow buffer extent");
    previousEnd = offset + length2;
    return { offset, length: length2 };
  });
  let compression;
  const compressionTable = fb.child(table, 3);
  if (compressionTable !== void 0) {
    const codec = fb.scalar(compressionTable, 0, "u8");
    if (codec !== 0 && codec !== 1 || fb.scalar(compressionTable, 1, "u8") !== 0) {
      throw new Error("Unsupported Arrow body compression");
    }
    compression = codec;
  }
  if (fb.vector(table, 4, 8).length) throw new Error("Unsupported Arrow variadic buffers");
  return { block, rows, nodes, buffers, compression, dictionaryId, delta };
}
function readFooter(source) {
  safeSize(source.size, "Arrow file size");
  if (source.size < 18 || decoder.decode(source.read(0, 6)) !== "ARROW1") throw new Error("Not an Arrow IPC file");
  const tail = source.read(source.size - 10, 10);
  if (decoder.decode(tail.subarray(4)) !== "ARROW1") throw new Error("Invalid Arrow file footer magic");
  const footerLength = new DataView(tail.buffer, tail.byteOffset, tail.byteLength).getUint32(0, true);
  if (!footerLength || footerLength > MAX_METADATA || footerLength > source.size - 18) throw new Error("Invalid Arrow footer length");
  const footerStart = source.size - 10 - footerLength;
  const fb = new FlatBuffer(source.read(footerStart, footerLength));
  const footer = fb.root();
  const version2 = fb.scalar(footer, 0, "i16");
  if (version2 !== 3 && version2 !== 4) throw new Error("Unsupported Arrow IPC metadata version");
  const schema = fb.child(footer, 1, true);
  if (fb.scalar(schema, 0, "i16") !== 0) throw new Error("Unsupported Arrow big-endian schema");
  let bufferIndex = 0;
  const fields = fb.tables(schema, 1).map((table) => {
    const field = parseField(fb, table, bufferIndex);
    bufferIndex += bufferCount(field);
    return field;
  });
  const features = fb.vector(schema, 3, 8);
  for (let i = 0; i < features.length; i++) {
    const feature = fb.i64(features.start + i * 8);
    if (feature !== 0n && feature !== 1n && feature !== 2n) throw new Error("Unsupported Arrow schema feature");
  }
  const allBlocks = [];
  const blocks = (index) => {
    const vector = fb.vector(footer, index, 24);
    return Array.from({ length: vector.length }, (_, i) => {
      const p = vector.start + i * 24;
      const block = { offset: fb.size(p), metadataLength: fb.i32(p + 8), bodyLength: fb.size(p + 16) };
      if (block.metadataLength < 4 || block.metadataLength > MAX_METADATA || block.offset < 8 || block.offset > footerStart - block.metadataLength - block.bodyLength) throw new Error("Invalid Arrow block extent");
      allBlocks.push(block);
      return block;
    });
  };
  const dictionaryBlocks = blocks(2), recordBlocks = blocks(3);
  allBlocks.sort((a, b) => a.offset - b.offset);
  for (let i = 1; i < allBlocks.length; i++) {
    const last = allBlocks[i - 1];
    if (allBlocks[i].offset < last.offset + last.metadataLength + last.bodyLength) throw new Error("Invalid Arrow overlapping blocks");
  }
  const batches = recordBlocks.map((block) => readBatch(source, block, false));
  const dictionaries = dictionaryBlocks.map((block) => readBatch(source, block, true));
  for (const batch of batches) {
    if (batch.nodes.length !== fields.length || batch.buffers.length !== bufferIndex) throw new Error("Invalid Arrow batch layout");
    fields.forEach((field, i) => {
      if (!field.nullable && batch.nodes[i].nullCount !== 0) throw new Error("Invalid Arrow nulls in non-nullable field");
    });
  }
  let rows = 0;
  for (const batch of batches) rows = safeSize(rows + batch.rows, "Arrow row count");
  return { fields, batches, dictionaries, rows, metadata: fb.metadata(schema, 2), customMetadata: fb.metadata(footer, 4) };
}
function readIpcBuffer(source, batch, index, maxBytes, expectedLength) {
  safeSize(expectedLength, "Arrow logical buffer length");
  if (expectedLength > maxBytes) throw new Error("Arrow decoded buffer exceeds max_buffer_bytes");
  const entry = batch.buffers[index];
  if (!entry) throw new Error("Invalid Arrow missing buffer");
  if (entry.length > maxBytes) throw new Error("Arrow stored buffer exceeds max_buffer_bytes");
  if (batch.compression === void 0 && entry.length !== expectedLength) throw new Error("Invalid Arrow buffer length does not match field layout");
  if (!entry.length && !expectedLength) return new Uint8Array();
  const raw = source.read(batch.block.offset + batch.block.metadataLength + entry.offset, entry.length);
  if (batch.compression === void 0) return raw;
  if (raw.length < 8) throw new Error("Invalid Arrow compressed buffer prefix");
  const expected = new DataView(raw.buffer, raw.byteOffset, raw.byteLength).getBigInt64(0, true);
  if (expected === -1n) {
    if (raw.length - 8 !== expectedLength) throw new Error("Invalid Arrow uncompressed buffer length");
    return raw.subarray(8);
  }
  if (expected < 0n || expected > BigInt(maxBytes)) throw new Error("Arrow decoded buffer exceeds max_buffer_bytes");
  if (expected !== BigInt(expectedLength)) throw new Error("Invalid Arrow declared decompressed buffer length");
  return decodeArrowBuffer(batch.compression, raw.subarray(8), Number(expected));
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
var DTA_MISSING = bytes_to_double(
  [127, 224, 0, 0, 0, 0, 0, 0]
);
var DTA_MISSING_A = bytes_to_double(
  [127, 224, 1, 0, 0, 0, 0, 0]
);
var DTA_MISSING_B = bytes_to_double(
  [127, 224, 2, 0, 0, 0, 0, 0]
);
var DTA_MISSING_Z = bytes_to_double(
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

// src/arrow-profile.ts
var ARROW_PROFILE_VERSION = "0";
var ARROW_PROFILE_VERSION_KEY = "dtatools:profile-version";
var ARROW_DATASET_KEY = "dtatools:dataset";
var ARROW_FIELD_KEY = "dtatools:field";
var ARROW_CHECKSUMS_KEY = "dtatools:checksums";
function malformed(detail) {
  throw new Error(`Malformed Arrow profile: ${detail}`);
}
function validateProfileVersion(version2) {
  if (version2 !== ARROW_PROFILE_VERSION) throw new Error(`Unsupported Arrow profile version ${version2}`);
}
function parseProfileJson(json) {
  let cursor = 0;
  const whitespace = () => {
    while (/[\t\n\r ]/.test(json[cursor] ?? "") && cursor < json.length) cursor++;
  };
  const string = () => {
    const start = cursor++;
    while (cursor < json.length) {
      const character = json[cursor++];
      if (character === "\\") cursor++;
      else if (character === '"') {
        let decoded;
        try {
          decoded = JSON.parse(json.slice(start, cursor));
        } catch {
          return malformed("invalid JSON string");
        }
        for (let index = 0; index < decoded.length; index++) {
          const code = decoded.charCodeAt(index);
          if (code >= 55296 && code <= 56319) {
            const low = decoded.charCodeAt(++index);
            if (!(low >= 56320 && low <= 57343)) malformed("unpaired JSON surrogate");
          } else if (code >= 56320 && code <= 57343) {
            malformed("unpaired JSON surrogate");
          }
        }
        return decoded;
      }
    }
    return malformed("unterminated JSON string");
  };
  const value = (depth) => {
    if (depth > 128) malformed("JSON nesting exceeds the profile limit");
    whitespace();
    if (json[cursor] === '"') return string();
    if (json[cursor] === "{") {
      cursor++;
      const object2 = /* @__PURE__ */ Object.create(null);
      whitespace();
      if (json[cursor] === "}") {
        cursor++;
        return object2;
      }
      while (cursor < json.length) {
        whitespace();
        if (json[cursor] !== '"') malformed("expected JSON object key");
        const key = string();
        if (Object.hasOwn(object2, key)) malformed(`duplicate JSON key ${key}`);
        whitespace();
        if (json[cursor++] !== ":") malformed("expected JSON colon");
        object2[key] = value(depth + 1);
        whitespace();
        const delimiter = json[cursor++];
        if (delimiter === "}") return object2;
        if (delimiter !== ",") malformed("expected JSON object delimiter");
      }
      return malformed("unterminated JSON object");
    }
    if (json[cursor] === "[") {
      cursor++;
      const array2 = [];
      whitespace();
      if (json[cursor] === "]") {
        cursor++;
        return array2;
      }
      while (cursor < json.length) {
        array2.push(value(depth + 1));
        whitespace();
        const delimiter = json[cursor++];
        if (delimiter === "]") return array2;
        if (delimiter !== ",") malformed("expected JSON array delimiter");
      }
      return malformed("unterminated JSON array");
    }
    const start = cursor;
    while (cursor < json.length && !/[\s,\]}]/.test(json[cursor])) cursor++;
    try {
      return JSON.parse(json.slice(start, cursor));
    } catch {
      return malformed("invalid JSON value");
    }
  };
  const result = value(0);
  whitespace();
  if (cursor !== json.length) malformed("trailing JSON content");
  return result;
}
function object(raw, keys) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) malformed("expected an object");
  const result = raw;
  if (keys) for (const key of Object.keys(result)) {
    if (!keys.includes(key)) malformed(`unknown field ${key}`);
  }
  return result;
}
function text(raw, context) {
  if (typeof raw !== "string") malformed(`${context} must be a string`);
  return raw;
}
function optionalText(raw, context) {
  return raw === void 0 || raw === null ? void 0 : text(raw, context);
}
function array(raw, context) {
  if (!Array.isArray(raw)) malformed(`${context} must be an array`);
  return raw;
}
function version(raw, context) {
  if (raw !== 0) malformed(`${context} document version ${String(raw)}`);
  return 0;
}
function metadata(raw) {
  const notes = array(raw.notes === void 0 ? [] : raw.notes, "notes");
  if (notes.length > 9999) malformed("notes may contain at most 9,999 entries");
  let previous = 0;
  const normalized = notes.map((entry, index) => {
    const note = typeof entry === "string" ? { number: index + 1, text: entry } : object(entry, ["number", "text"]);
    if (typeof note.number !== "number" || !Number.isInteger(note.number) || note.number <= previous || note.number > 9999) {
      malformed("notes require unique ascending numbers from 1 through 9999");
    }
    previous = note.number;
    return { number: note.number, text: text(note.text, "note text") };
  });
  const characteristics = array(raw.characteristics === void 0 ? [] : raw.characteristics, "characteristics").map((entry) => {
    const characteristic = object(entry, ["name", "value"]);
    return { name: text(characteristic.name, "characteristic name"), value: text(characteristic.value, "characteristic value") };
  });
  try {
    return { notes: listStataNotes({ notes: normalized }), characteristics: listStataCharacteristics({ characteristics }) };
  } catch (error) {
    return malformed(error instanceof Error ? error.message : "invalid Stata metadata");
  }
}
function validateDatasetDocument(raw, selectedValueLabels) {
  const document = object(
    raw === void 0 ? { version: 0 } : raw,
    ["version", "output_container", "label", "notes", "characteristics", "value_labels"]
  );
  const output_container = optionalText(document.output_container, "output_container");
  if (output_container !== void 0 && (!output_container || output_container.trim() !== output_container)) {
    malformed("output_container must be a nonempty name without surrounding whitespace");
  }
  const registry = object(document.value_labels ?? {});
  const names = Object.keys(registry);
  if (names.length > 12e4) malformed("value-label registry may contain at most 120,000 tables");
  const value_labels = /* @__PURE__ */ Object.create(null);
  for (const name of names) {
    const entries = array(registry[name], "value-label table").map((rawEntry) => {
      const entry = object(rawEntry, ["value", "tag", "label"]);
      const value = entry.value ?? void 0;
      const tag = entry.tag ?? void 0;
      if (value === void 0 === (tag === void 0)) malformed("value-label entry must contain exactly one of value or tag");
      if (value !== void 0 && (typeof value !== "number" || !Number.isInteger(value) || value < -2147483648 || value > 2147483647)) malformed("value-label value must be an int32");
      if (tag !== void 0 && (typeof tag !== "string" || !/^\.[a-z]$/.test(tag))) {
        malformed("value-label tag must be extended missing .a through .z");
      }
      return { ...value !== void 0 ? { value } : { tag }, label: text(entry.label, "value-label label") };
    });
    if (selectedValueLabels === void 0 || selectedValueLabels.has(name)) value_labels[name] = entries;
  }
  return {
    version: version(document.version, "dataset"),
    ...output_container !== void 0 ? { output_container } : {},
    label: document.label === void 0 ? "" : text(document.label, "label"),
    ...metadata(document),
    value_labels
  };
}
var STORAGE_TYPES = { byte: "int8", int: "int16", long: "int32", float: "float32", double: "float64" };
var DOUBLE_TYPES = ["float32", "float64", "int64", "uint16", "uint32", "uint64"];
function validateFieldDocument(raw, field) {
  const source = object(raw, [
    "version",
    "label",
    "format",
    "notes",
    "characteristics",
    "storage",
    "string_storage",
    "value_labels",
    "missing",
    "missing_release",
    "r"
  ]);
  const fail2 = (message) => malformed(`field ${field.name} ${message}`);
  const storage = optionalText(source.storage, "storage");
  if (storage !== void 0 && !Object.hasOwn(STORAGE_TYPES, storage)) fail2("declares invalid Stata storage");
  const missing = optionalText(source.missing, "missing");
  if (missing !== void 0 && missing !== "sentinel" && missing !== "payload") fail2("declares invalid missing encoding");
  const missing_release = source.missing_release ?? void 0;
  if (missing_release !== void 0 && ![105, 108, 110, 111, 113, 114, 115, 117, 118, 119].includes(missing_release)) {
    fail2("declares invalid missing_release");
  }
  let r;
  if (source.r !== void 0 && source.r !== null) {
    const semantics = object(source.r, ["class", "ordered", "tz", "units"]);
    if (semantics.ordered !== void 0 && semantics.ordered !== null && typeof semantics.ordered !== "boolean") fail2("r.ordered must be boolean");
    r = {
      class: text(semantics.class, "r.class"),
      ...semantics.ordered != null ? { ordered: semantics.ordered } : {},
      ...semantics.tz != null ? { tz: text(semantics.tz, "r.tz") } : {},
      ...semantics.units != null ? { units: text(semantics.units, "r.units") } : {}
    };
  }
  const document = {
    version: version(source.version, "field"),
    label: source.label === void 0 ? "" : text(source.label, "label"),
    format: source.format === void 0 ? "" : text(source.format, "format"),
    ...metadata(source),
    ...storage !== void 0 ? { storage } : {},
    ...missing !== void 0 ? { missing } : {},
    ...missing_release !== void 0 ? { missing_release } : {},
    ...r !== void 0 ? { r } : {}
  };
  const stringStorage = optionalText(source.string_storage, "string_storage");
  const valueLabels = optionalText(source.value_labels, "value_labels");
  if (stringStorage !== void 0) {
    document.string_storage = stringStorage;
    if (stringStorage !== "strL" && (!/^str[1-9][0-9]*$/.test(stringStorage) || Number(stringStorage.slice(3)) > 2045)) fail2("declares invalid string storage");
    if (storage !== void 0 || field.type !== "utf8") fail2("declares string storage incompatible with Arrow type");
  }
  if (valueLabels !== void 0) document.value_labels = valueLabels;
  if (storage !== void 0) {
    if (field.type !== STORAGE_TYPES[storage]) fail2("declares Stata storage incompatible with Arrow type");
    if (missing !== (storage === "float" || storage === "double" ? "payload" : "sentinel")) fail2("declares missing encoding incompatible with Stata storage");
    if (missing_release !== void 0 && storage === "double") fail2("declares source missing release for double storage");
    if (field.nullable) fail2("declares raw Stata missing storage on a nullable field");
    if (r && (!["dta_numeric", "stata_numeric"].includes(r.class) || r.ordered !== void 0 || r.tz !== void 0 || r.units !== void 0)) fail2("declares R semantics incompatible with Stata storage");
    return document;
  }
  if (missing_release !== void 0) fail2("declares source missing release without Stata storage");
  if (missing === "sentinel") fail2("declares sentinel encoding without Stata storage");
  if (missing === "payload" && (field.type !== "float64" || field.nullable || !r || !["double", "haven_labelled", "Date", "POSIXct", "difftime"].includes(r.class))) fail2("declares incompatible payload missing semantics");
  if (r) {
    const compatible = {
      logical: field.type === "bool",
      integer: ["int8", "int16", "int32", "uint8"].includes(field.type),
      double: DOUBLE_TYPES.includes(field.type),
      character: ["utf8", "large-utf8"].includes(field.type),
      factor: field.type === "dictionary" && field.dictionaryKeyType === "int32" && ["utf8", "large-utf8"].includes(field.dictionaryValueType ?? ""),
      raw: field.type === "uint8",
      Date: ["date32", "float64"].includes(field.type),
      POSIXct: ["timestamp", "float64"].includes(field.type),
      difftime: ["duration", "float64"].includes(field.type),
      haven_labelled: field.type === "float64"
    };
    if (!Object.hasOwn(compatible, r.class) || !compatible[r.class]) fail2(`declares unsupported or incompatible R class ${r.class}`);
    if (r.ordered !== void 0 && r.class !== "factor") fail2("declares r.ordered without factor semantics");
    if (r.tz !== void 0 && r.class !== "POSIXct") fail2("declares r.tz without POSIXct semantics");
    if (r.units !== void 0 && (r.class !== "difftime" || !["secs", "mins", "hours", "days", "weeks"].includes(r.units))) fail2("declares unsupported difftime units");
  }
  if (valueLabels !== void 0 && ![...DOUBLE_TYPES, "date32", "timestamp", "duration"].includes(field.type)) fail2("declares value labels incompatible with Arrow type");
  return document;
}
function validateValueLabelReference(field, document, dataset) {
  if (document.value_labels !== void 0 && !Object.hasOwn(dataset.value_labels, document.value_labels)) {
    malformed(`field ${field.name} refers to missing value-label table ${document.value_labels}`);
  }
}
function validateChecksumsDocument(raw) {
  const document = object(raw, ["version", "algorithm", "batches", "dictionaries"]);
  if (document.algorithm !== "xxh64") malformed("unknown checksum algorithm");
  const hashes2 = (rawHashes) => array(rawHashes, "checksums").map((hash) => text(hash, "checksum"));
  const batches = array(document.batches, "checksum batches").map((rawBatch) => {
    const batch = object(rawBatch, ["columns"]);
    return { columns: array(batch.columns, "checksum columns").map(hashes2) };
  });
  const dictionaries = /* @__PURE__ */ Object.create(null);
  const registry = object(document.dictionaries === void 0 ? {} : document.dictionaries);
  for (const name of Object.keys(registry)) dictionaries[name] = hashes2(registry[name]);
  return { version: version(document.version, "checksums"), algorithm: "xxh64", batches, dictionaries };
}
function classifyProfileMissing(bytes, offset, document) {
  if (document.missing === void 0) return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const modern = (document.missing_release ?? 118) >= 113;
  let code = -1;
  switch (document.storage) {
    case "byte":
      code = byte_missing_offset(view.getInt8(offset), modern);
      break;
    case "int":
      code = int_missing_offset(view.getInt16(offset, true), modern);
      break;
    case "long":
      code = long_missing_offset(view.getInt32(offset, true), modern);
      break;
    case "float":
      code = float_missing_offset(view.getUint32(offset, true), modern);
      break;
    case "double": {
      const tag = classify_raw_double_missing_at(view, offset, true);
      return tag === null ? null : make_missing_value(tag);
    }
    default: {
      const bits = view.getBigUint64(offset, true);
      const ignored = 0x800800ff00000000n;
      const mask = 0xffffffffffffffffn ^ ignored;
      if ((bits & mask) !== (0x7ff00000000007a2n & mask)) return null;
      const tag = Number(bits >> 32n & 255n);
      code = tag === 0 ? 0 : tag >= 97 && tag <= 122 ? tag - 96 : -1;
    }
  }
  return code < 0 ? null : missing_value_from_offset(code);
}

// src/arrow-reader.ts
var textDecoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
function bit(bytes, index) {
  return (bytes[index >> 3] & 1 << (index & 7)) !== 0;
}
function abortArrowRead(signal) {
  if (signal?.aborted) throw new DOMException("The Arrow read was aborted", "AbortError");
}
function clone(value) {
  return structuredClone(value);
}
function verifyHashes(actual, expected, field) {
  if (!expected || expected.length !== actual.length) throw new Error(`Malformed Arrow profile: missing buffer checksums for ${field}`);
  if (expected.some((hash) => !/^[0-9a-fA-F]{16}$/.test(hash))) throw new Error("Malformed Arrow profile: invalid checksum");
  if (actual.some((hash, i) => hash !== expected[i].toLowerCase())) throw new Error(`Arrow checksum mismatch for ${field}`);
}
function hashes(array2, field) {
  return canonicalBufferHashes({
    type: array2.type,
    length: array2.length,
    validity: array2.validity,
    buffers: array2.buffers,
    dictionaryKeyType: field.dictionaryKeyType
  });
}
var ArrowReader = class {
  constructor(source, options = {}) {
    this.source = source;
    for (const key of ["profile", "verify"]) {
      if (options[key] !== void 0 && typeof options[key] !== "boolean") throw new Error(`${key} must be a boolean`);
    }
    this.maxBytes = safeSize(options.max_buffer_bytes ?? 256 * 1024 * 1024, "max_buffer_bytes");
    if (!this.maxBytes) throw new Error("max_buffer_bytes must be positive");
    this.maxRows = options.max_output_rows === void 0 ? void 0 : safeSize(options.max_output_rows, "max_output_rows");
    this.applyProfile = options.profile !== false;
    this.verify = options.verify !== false && this.applyProfile;
    this.footer = readFooter(source);
    if (this.applyProfile) {
      this.profileVersion = this.footer.metadata.get(ARROW_PROFILE_VERSION_KEY);
      if (this.profileVersion !== void 0) validateProfileVersion(this.profileVersion);
    }
  }
  source;
  footer;
  applyProfile;
  verify;
  maxBytes;
  maxRows;
  dictionaryCache = /* @__PURE__ */ new Map();
  profileVersion;
  get nobs() {
    return this.footer.rows;
  }
  get nvar() {
    return this.footer.fields.length;
  }
  allIndices() {
    return this.footer.fields.map((_, i) => i);
  }
  selectionProfile(indices) {
    const result = { fields: /* @__PURE__ */ new Map() };
    if (this.profileVersion === void 0) return result;
    const references = /* @__PURE__ */ new Set();
    for (const index of indices) {
      const field = this.footer.fields[index];
      const raw = field.custom_metadata.get(ARROW_FIELD_KEY);
      if (raw === void 0) continue;
      const document = validateFieldDocument(parseProfileJson(raw), field);
      result.fields.set(index, document);
      if (document.value_labels !== void 0) references.add(document.value_labels);
    }
    const datasetRaw = this.footer.metadata.get(ARROW_DATASET_KEY);
    result.dataset = validateDatasetDocument(
      datasetRaw === void 0 ? void 0 : parseProfileJson(datasetRaw),
      indices.length === this.nvar ? void 0 : references
    );
    for (const [index, document] of result.fields) validateValueLabelReference(this.footer.fields[index], document, result.dataset);
    if (this.verify) {
      const raw = this.footer.customMetadata.get(ARROW_CHECKSUMS_KEY);
      if (raw === void 0) throw new Error("Malformed Arrow profile: missing checksums document");
      result.checksums = validateChecksumsDocument(parseProfileJson(raw));
      if (result.checksums.batches.length !== this.footer.batches.length) throw new Error("Malformed Arrow profile: checksum batch count mismatch");
    }
    return result;
  }
  /** Accessing complete metadata consumes every profile field document. */
  get metadata() {
    const profile = this.selectionProfile(this.allIndices());
    const variables = this.footer.fields.map((field, index) => {
      const { bufferIndex: _, dictionaryId: __, ...variable } = field;
      const copy = clone(variable);
      if (profile.fields.has(index)) copy.profile = clone(profile.fields.get(index));
      if (field.type === "date32") copy.epoch = "1970-01-01";
      if (field.type === "timestamp") copy.epoch = field.timezone ? "1970-01-01T00:00:00Z" : "1970-01-01T00:00:00";
      const semantics = copy.profile?.r;
      if (semantics?.class === "Date") copy.temporal_semantics = { unit: "days", epoch: "1970-01-01" };
      if (semantics?.class === "POSIXct") copy.temporal_semantics = { unit: "secs", epoch: "1970-01-01T00:00:00Z", timezone: semantics.tz };
      if (semantics?.class === "difftime") copy.temporal_semantics = { unit: semantics.units ?? "secs" };
      if (!this.applyProfile) copy.custom_metadata.delete(ARROW_FIELD_KEY);
      return copy;
    });
    const custom_metadata = new Map(this.footer.metadata), footer_metadata = new Map(this.footer.customMetadata);
    if (!this.applyProfile) {
      custom_metadata.delete(ARROW_PROFILE_VERSION_KEY);
      custom_metadata.delete(ARROW_DATASET_KEY);
      footer_metadata.delete(ARROW_CHECKSUMS_KEY);
    }
    return {
      nobs: this.nobs,
      nvar: this.nvar,
      profile_version: this.profileVersion,
      dataset: clone(profile.dataset),
      variables,
      custom_metadata,
      footer_metadata
    };
  }
  get variables() {
    return this.metadata.variables;
  }
  normalizeColumns(indices) {
    const output = [], seen = /* @__PURE__ */ new Set();
    for (const index of indices) {
      safeSize(index, "Arrow column index");
      if (index >= this.nvar) throw new Error(`Arrow column index ${index} is out of bounds`);
      if (!seen.has(index)) {
        seen.add(index);
        output.push(index);
      }
    }
    return output;
  }
  rowColumns(start = 0, end = this.nvar) {
    safeSize(start, "col_start");
    safeSize(end, "col_end");
    if (start > end || end > this.nvar) throw new Error("Arrow column range is out of bounds");
    return Array.from({ length: end - start }, (_, i) => start + i);
  }
  window(start, count) {
    safeSize(start, "Arrow row start");
    safeSize(count, "Arrow row count");
    const actual = Math.min(count, Math.max(0, this.nobs - start));
    if (this.maxRows !== void 0 && actual > this.maxRows) throw new Error("Arrow selection exceeds max_output_rows");
    if (actual > 4294967295) throw new Error("Arrow selection exceeds JavaScript array capacity");
    return { start: Math.min(start, this.nobs), count: actual };
  }
  loadArray(batch, field, nodeIndex) {
    const node = batch.nodes[nodeIndex];
    if (!node || batch.buffers.length < field.bufferIndex + bufferCount(field)) throw new Error("Invalid Arrow array layout");
    const read = (index, expected) => readIpcBuffer(this.source, batch, field.bufferIndex + index, this.maxBytes, expected);
    const validity = node.nullCount ? read(0, Math.ceil(node.length / 8)) : void 0;
    if (validity && validity.length < Math.ceil(node.length / 8)) throw new Error("Invalid Arrow validity bitmap length");
    if (validity) {
      let count = 0;
      for (let i = 0; i < node.length; i++) if (!bit(validity, i)) count++;
      if (count !== node.nullCount) throw new Error("Invalid Arrow validity bitmap null count");
    }
    const type = field.type;
    const stringWidth = type === "utf8" ? 4 : type === "large-utf8" ? 8 : 0;
    const firstLength = stringWidth ? (node.length + 1) * stringWidth : type === "bool" ? Math.ceil(node.length / 8) : node.length * physicalWidth(type === "dictionary" ? field.dictionaryKeyType : type);
    const buffers = [read(1, firstLength)];
    if (stringWidth) {
      const offsets = new DataView(buffers[0].buffer, buffers[0].byteOffset, buffers[0].byteLength);
      const last = stringWidth === 4 ? BigInt(offsets.getInt32(node.length * 4, true)) : offsets.getBigInt64(node.length * 8, true);
      if (last < 0n || last > BigInt(this.maxBytes)) throw new Error("Invalid Arrow string data length exceeds max_buffer_bytes");
      buffers.push(read(2, Number(last)));
    }
    const data = buffers[0];
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    let value;
    if (type === "utf8" || type === "large-utf8") {
      const width = type === "utf8" ? 4 : 8;
      if (data.length < (node.length + 1) * width) throw new Error("Invalid Arrow string offsets length");
      const stringData = buffers[1];
      const offset = (i) => {
        const position = width === 4 ? BigInt(view.getInt32(i * width, true)) : view.getBigInt64(i * width, true);
        if (position < 0n || position > BigInt(stringData.length)) throw new Error("Invalid Arrow string offset");
        return Number(position);
      };
      let previous = offset(0);
      for (let i = 1; i <= node.length; i++) {
        const current = offset(i);
        if (current < previous) throw new Error("Invalid Arrow decreasing string offsets");
        textDecoder.decode(stringData.subarray(previous, current));
        previous = current;
      }
      value = (i) => textDecoder.decode(stringData.subarray(offset(i), offset(i + 1)));
    } else if (type === "bool") {
      if (data.length < Math.ceil(node.length / 8)) throw new Error("Invalid Arrow boolean buffer length");
      value = (i) => bit(data, i);
    } else {
      const physical = type === "dictionary" ? field.dictionaryKeyType : type;
      const width = physicalWidth(physical);
      if (data.length < node.length * width) throw new Error("Invalid Arrow value buffer length");
      const getters = {
        int8: (p) => view.getInt8(p),
        uint8: (p) => view.getUint8(p),
        int16: (p) => view.getInt16(p, true),
        uint16: (p) => view.getUint16(p, true),
        int32: (p) => view.getInt32(p, true),
        uint32: (p) => view.getUint32(p, true),
        int64: (p) => view.getBigInt64(p, true),
        uint64: (p) => view.getBigUint64(p, true),
        float32: (p) => view.getFloat32(p, true),
        float64: (p) => view.getFloat64(p, true),
        date32: (p) => view.getInt32(p, true),
        timestamp: (p) => view.getBigInt64(p, true),
        duration: (p) => view.getBigInt64(p, true)
      };
      value = (i, profile) => {
        const p = i * width;
        if (profile) {
          const missing = classifyProfileMissing(data, p, profile);
          if (missing) return missing;
        }
        return getters[physical](p);
      };
    }
    return {
      type,
      length: node.length,
      validity,
      buffers,
      cell: (i, profile) => validity && !bit(validity, i) ? null : value(i, profile)
    };
  }
  dictionary(field) {
    const id = field.dictionaryId;
    const cached = this.dictionaryCache.get(id);
    if (cached) return cached;
    const sourceFields = this.footer.fields.filter((other) => other.dictionaryId === id);
    if (sourceFields.some((other) => other.dictionaryValueType !== field.dictionaryValueType)) throw new Error("Invalid Arrow dictionary has conflicting value types");
    const chunks = [];
    for (const batch of this.footer.dictionaries) {
      if (batch.dictionaryId !== id) continue;
      if (batch.nodes.length !== 1 || batch.buffers.length !== 3) throw new Error("Invalid Arrow dictionary batch layout");
      if (batch.delta && !chunks.length) throw new Error("Invalid Arrow delta dictionary has no preceding dictionary");
      if (!batch.delta) chunks.length = 0;
      chunks.push(this.loadArray(batch, { ...field, type: field.dictionaryValueType, bufferIndex: 0 }, 0));
    }
    if (!chunks.length) throw new Error(`Invalid Arrow missing dictionary ${id}`);
    let result;
    if (chunks.length === 1) result = chunks[0];
    else {
      const length = chunks.reduce((sum, chunk) => safeSize(sum + chunk.length, "Arrow dictionary length"), 0);
      const width = field.dictionaryValueType === "utf8" ? 4 : 8;
      const bytes = chunks.reduce((sum, chunk) => sum + chunk.buffers[1].length, 0);
      if (bytes > this.maxBytes || (length + 1) * width > this.maxBytes) throw new Error("Arrow dictionary exceeds max_buffer_bytes");
      const offsets = new Uint8Array((length + 1) * width), strings = new Uint8Array(bytes), validity = new Uint8Array(Math.ceil(length / 8));
      const offsetView = new DataView(offsets.buffer);
      const levels = [];
      const encoder = new TextEncoder();
      let position = 0, nulls = false;
      for (const chunk of chunks) for (let i = 0; i < chunk.length; i++) {
        const cell = chunk.cell(i), index = levels.length;
        levels.push(cell);
        if (cell !== null) {
          validity[index >> 3] |= 1 << (index & 7);
          const encoded = encoder.encode(cell);
          strings.set(encoded, position);
          position += encoded.length;
        } else nulls = true;
        if (width === 4) offsetView.setInt32((index + 1) * width, position, true);
        else offsetView.setBigInt64((index + 1) * width, BigInt(position), true);
      }
      result = {
        type: field.dictionaryValueType,
        length,
        validity: nulls ? validity : void 0,
        buffers: [offsets, strings.subarray(0, position)],
        cell: (i) => levels[i]
      };
    }
    this.dictionaryCache.set(id, result);
    return result;
  }
  get_dictionary(index) {
    this.normalizeColumns([index]);
    const field = this.footer.fields[index];
    if (field.dictionaryId === void 0) return void 0;
    const profile = this.selectionProfile([index]);
    const array2 = this.dictionary(field);
    if (profile.checksums) verifyHashes(hashes(array2, field), profile.checksums.dictionaries[String(index)], field.name);
    if (array2.length > 4294967295) throw new Error("Arrow dictionary exceeds JavaScript array capacity");
    return {
      ordered: profile.fields.get(index)?.r?.ordered ?? field.dictionaryOrdered ?? false,
      levels: Array.from({ length: array2.length }, (_, i) => array2.cell(i))
    };
  }
  get dictionaries() {
    const result = /* @__PURE__ */ new Map();
    for (const index of this.allIndices()) {
      const dictionary = this.get_dictionary(index);
      if (dictionary) result.set(index, dictionary);
    }
    return result;
  }
  *chunks(indices, start, count, options = {}) {
    abortArrowRead(options.signal);
    const selected = this.normalizeColumns(indices), window = this.window(start, count);
    const chunkRows = safeSize(options.chunk_rows ?? 65536, "chunk_rows");
    if (!chunkRows) throw new Error("chunk_rows must be positive");
    const profile = this.selectionProfile(selected);
    const dictionaries = /* @__PURE__ */ new Map();
    for (const index of selected) {
      abortArrowRead(options.signal);
      const field = this.footer.fields[index];
      if (field.dictionaryId !== void 0) {
        const dictionary = this.dictionary(field);
        if (profile.checksums) verifyHashes(hashes(dictionary, field), profile.checksums.dictionaries[String(index)], field.name);
        dictionaries.set(index, dictionary);
      }
    }
    let batchStart = 0;
    for (let batchIndex = 0; batchIndex < this.footer.batches.length; batchIndex++) {
      const batch = this.footer.batches[batchIndex];
      const first = Math.max(window.start - batchStart, 0);
      const last = Math.min(window.start + window.count - batchStart, batch.rows);
      batchStart += batch.rows;
      if (first >= last) continue;
      const arrays = /* @__PURE__ */ new Map();
      for (const index of selected) {
        abortArrowRead(options.signal);
        const field = this.footer.fields[index];
        const array2 = this.loadArray(batch, field, index);
        if (profile.checksums) verifyHashes(hashes(array2, field), profile.checksums.batches[batchIndex]?.columns[index], `${field.name}, batch ${batchIndex}`);
        const dictionary = dictionaries.get(index);
        if (dictionary) for (let row = 0; row < array2.length; row++) {
          const code = array2.cell(row);
          if (code !== null && (BigInt(code) < 0n || BigInt(code) >= BigInt(dictionary.length))) throw new Error("Invalid Arrow dictionary index");
        }
        arrays.set(index, array2);
      }
      for (let offset = first; offset < last; offset += chunkRows) {
        abortArrowRead(options.signal);
        const length = Math.min(last - offset, chunkRows), result = /* @__PURE__ */ new Map();
        for (const index of selected) result.set(index, Array.from({ length }, (_, i) => arrays.get(index).cell(offset + i, profile.fields.get(index))));
        yield result;
      }
    }
  }
};
var ArrowBuffer = class _ArrowBuffer {
  constructor(reader) {
    this.reader = reader;
  }
  reader;
  static open(buffer, options = {}) {
    const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
    const source = { size: bytes.byteLength, read(offset, length) {
      safeSize(offset, "Arrow read offset");
      safeSize(length, "Arrow read length");
      if (offset > bytes.length - length) throw new Error("Unexpected EOF reading Arrow buffer");
      return bytes.subarray(offset, offset + length);
    } };
    return new _ArrowBuffer(new ArrowReader(source, options));
  }
  get nobs() {
    return this.reader.nobs;
  }
  get nvar() {
    return this.reader.nvar;
  }
  get metadata() {
    return this.reader.metadata;
  }
  get variables() {
    return this.reader.variables;
  }
  get dictionaries() {
    return this.reader.dictionaries;
  }
  get_dictionary(index) {
    return this.reader.get_dictionary(index);
  }
  read_rows(start, count, col_start = 0, col_end = this.nvar, options = {}) {
    const columns = this.reader.rowColumns(col_start, col_end), window = this.reader.window(start, count);
    const rows = [];
    for (const chunk of this.reader.chunks(columns, start, count, options)) {
      const length = columns.length ? chunk.get(columns[0]).length : 0;
      for (let i = 0; i < length; i++) rows.push(columns.map((index) => chunk.get(index)[i]));
    }
    if (!columns.length) return Array.from({ length: window.count }, () => []);
    return rows;
  }
  read_columns(indices, options = {}) {
    const columns = this.reader.normalizeColumns(indices), result = new Map(columns.map((index) => [index, []]));
    for (const chunk of this.reader.chunks(columns, 0, this.nobs, options)) {
      for (const index of columns) for (const cell of chunk.get(index)) result.get(index).push(cell);
    }
    return result;
  }
};

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
function legacy_layout_for_version(version2) {
  return LAYOUTS[version2];
}
function legacy_expansion_header_size(layout) {
  return 1 + layout.expansion_length_width;
}

// src/legacy-header.ts
var SORTLIST_ENTRY_WIDTH = 2;
function read_fixed_string2(bytes, offset, field_width, decoder2) {
  let my_end = offset;
  const my_limit = offset + field_width;
  while (my_end < my_limit && bytes[my_end] !== 0) {
    my_end++;
  }
  return decoder2.decode(
    bytes.subarray(offset, my_end)
  );
}
function legacy_metadata_buffer_size(nvar, format_version) {
  return legacy_metadata_fixed_size(nvar, format_version) + 65536;
}
function legacy_metadata_fixed_size(nvar, format_version) {
  const layout = legacy_layout_for_version(format_version);
  const my_sections_size = nvar + nvar * layout.varname_width + (nvar + 1) * SORTLIST_ENTRY_WIDTH + nvar * layout.format_width + nvar * layout.value_label_name_width + nvar * layout.variable_label_width;
  return layout.header_size + my_sections_size;
}
function frame_expansion_fields(view, little_endian, start, buffer_length, format_version, plan) {
  let pos = start;
  const layout = legacy_layout_for_version(format_version);
  const my_header_size = legacy_expansion_header_size(layout);
  while (pos + my_header_size <= buffer_length) {
    const my_data_type = view.getUint8(pos);
    const my_len = layout.expansion_length_width === 2 ? view.getInt16(pos + 1, little_endian) : view.getInt32(pos + 1, little_endian);
    pos += my_header_size;
    if (my_data_type === 0 && my_len === 0) {
      return pos;
    }
    if (my_data_type === 0 || my_len < 0) {
      throw new Error("Invalid legacy expansion field");
    }
    if (pos + my_len > buffer_length) {
      throw new Error("Truncated legacy expansion field");
    }
    if (my_data_type === 1 && my_len >= 2 * layout.varname_width) {
      plan.add({
        namesStart: pos,
        nameWidth: layout.varname_width,
        valueStart: pos + 2 * layout.varname_width,
        valueLength: my_len - 2 * layout.varname_width
      });
    }
    pos += my_len;
  }
  throw new Error("Missing legacy expansion-field terminator");
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
    the_variables.push(withLazyStataMetadata({
      name: the_varnames[i],
      type: legacy_type_code_to_dta_type(my_code, format_version),
      type_code: my_code,
      format: the_formats[i],
      label: the_variable_labels[i],
      value_label_name: the_value_label_names[i],
      byte_width: my_width,
      byte_offset: my_running_offset
    }));
    my_running_offset += my_width;
  }
  const obs_length = my_running_offset;
  const notes = [];
  const characteristics = [];
  const my_expansion_offset = pos;
  const collector = new StataMetadataCollector(
    { notes, characteristics },
    the_variables
  );
  const plan = new StataCharacteristicFramePlan(
    bytes,
    my_decoder,
    collector
  );
  const my_data_offset = frame_expansion_fields(
    view,
    little_endian,
    pos,
    buffer.byteLength,
    format_version,
    plan
  );
  plan.finish();
  const my_value_labels_offset = Number(
    BigInt(my_data_offset) + BigInt(nobs) * BigInt(obs_length)
  );
  if (!Number.isSafeInteger(my_value_labels_offset) || my_value_labels_offset > file_size) {
    throw new Error("Truncated legacy observation data");
  }
  const section_offsets = {
    dta_data: 0,
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
    dta_data_close: file_size,
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

// src/data-reader.ts
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
function assert_observation_bytes(bytes, start, count, width) {
  const end = start + count * width;
  if (!Number.isSafeInteger(start) || start < 0 || !Number.isSafeInteger(end) || end < start || end > bytes.length) {
    throw new Error("Truncated observation data or unsafe observation extent");
  }
}
function expect_data_tag(bytes, offset, tag) {
  if (!Number.isSafeInteger(offset) || offset < 0 || offset + tag.length > bytes.length) {
    throw new Error(`Truncated ${tag} tag`);
  }
  for (let i = 0; i < tag.length; i++) {
    if (bytes[offset + i] !== tag.charCodeAt(i)) throw new Error(`Missing ${tag} tag`);
  }
  return offset + tag.length;
}
function validate_data_section(bytes, metadata2) {
  const offsets = metadata2.section_offsets;
  const modern = !is_legacy_format(metadata2.format_version);
  const start = modern ? expect_data_tag(bytes, offsets.data, "<data>") : offsets.data;
  assert_observation_bytes(bytes, start, metadata2.nobs, metadata2.obs_length);
  const end = start + metadata2.nobs * metadata2.obs_length;
  if (!modern) {
    if (end !== offsets.value_labels) throw new Error("Observation extent does not match value-label offset");
    return start;
  }
  if (expect_data_tag(bytes, end, "</data>") !== offsets.strls) {
    throw new Error("Observation extent does not match strL offset");
  }
  const after_open = expect_data_tag(bytes, offsets.strls, "<strls>");
  const close = offsets.value_labels - "</strls>".length;
  if (close < after_open) throw new Error("Invalid strL section extent");
  expect_data_tag(bytes, close, "</strls>");
  return start;
}
function decoder_for_metadata(metadata2) {
  switch (metadata2.text_encoding) {
    case "utf-8":
    case "windows-1252":
    case "iso-8859-1":
      return text_decoder(metadata2.text_encoding);
    default:
      return text_decoder(resolve_text_encoding(
        metadata2.format_version,
        metadata2.text_encoding
      ));
  }
}
function read_fixed_string3(bytes, offset, width, decoder2) {
  if (width === 0 || bytes[offset] === 0) return "";
  let my_end = offset + 1;
  const my_limit = offset + width;
  while (my_end < my_limit && bytes[my_end] !== 0) {
    my_end++;
  }
  return decode_text_range(decoder2, bytes, offset, my_end);
}
function read_cell(view, bytes, offset, variable_type, byte_width, little_endian, modern_missing, decoder2, format_version) {
  let my_missing = -1;
  switch (variable_type) {
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
        byte_width,
        decoder2
      );
  }
}
function decode_single_column_into_rows(view, bytes, rows, output_start, count, row_base_offset, variable, row_width, little_endian, modern_missing, decoder2, format_version) {
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
          decoder2
        )];
      }
  }
}
function read_rows_from_view(view, bytes, metadata2, row_base_offset, start, count, col_start, col_end, out, out_offset = 0) {
  if (metadata2.nobs === 0 || start < 0 || count <= 0 || start >= metadata2.nobs) {
    return out ?? [];
  }
  const my_actual_count = Math.min(count, metadata2.nobs - start);
  const my_col_start = Math.max(0, col_start ?? 0);
  const my_col_end = Math.min(
    metadata2.nvar,
    col_end ?? metadata2.nvar
  );
  if (my_col_start >= my_col_end) return out ?? [];
  assert_observation_bytes(bytes, row_base_offset, my_actual_count, metadata2.obs_length);
  const little_endian = metadata2.byte_order === "LSF";
  const modern_missing = metadata2.format_version >= 113;
  const my_decoder = decoder_for_metadata(metadata2);
  const the_rows = out ?? new Array(my_actual_count);
  const my_column_count = my_col_end - my_col_start;
  const packed = isPackedDtaReadPlan(metadata2);
  if (my_column_count === 1) {
    const variable = packed ? metadata2.variable(my_col_start) : metadata2.variables[my_col_start];
    if (variable === void 0) return the_rows;
    decode_single_column_into_rows(
      view,
      bytes,
      the_rows,
      out_offset,
      my_actual_count,
      row_base_offset,
      variable,
      metadata2.obs_length,
      little_endian,
      modern_missing,
      my_decoder,
      metadata2.format_version
    );
    return the_rows;
  }
  for (let i = 0; i < my_actual_count; i++) {
    const my_row = new Array(my_column_count);
    const my_row_offset = row_base_offset + i * metadata2.obs_length;
    for (let my_abs_col = my_col_start, my_output_col = 0; my_abs_col < my_col_end; my_abs_col++, my_output_col++) {
      const my_variable = packed ? void 0 : metadata2.variables[my_abs_col];
      const variableType = packed ? metadata2.variable_types[my_abs_col] : my_variable.type;
      const byteWidth = packed ? metadata2.variable_byte_widths[my_abs_col] : my_variable.byte_width;
      const byteOffset = packed ? metadata2.variable_byte_offsets[my_abs_col] : my_variable.byte_offset;
      my_row[my_output_col] = read_cell(
        view,
        bytes,
        my_row_offset + byteOffset,
        variableType,
        byteWidth,
        little_endian,
        modern_missing,
        my_decoder,
        metadata2.format_version
      );
    }
    the_rows[out_offset + i] = my_row;
  }
  return the_rows;
}
function read_rows_from_buffer(buffer, metadata2, start, count, col_start, col_end) {
  assert_valid_row_range(start, count);
  const { view, bytes } = buffer_views(buffer);
  const my_data_start = validate_data_section(bytes, metadata2);
  return read_rows_from_view(
    view,
    bytes,
    metadata2,
    my_data_start + start * metadata2.obs_length,
    start,
    count,
    col_start,
    col_end
  );
}
function read_rows_from_data_buffer(buffer, metadata2, start, count, col_start, col_end, out, out_offset = 0) {
  assert_valid_row_range(start, count);
  const { view, bytes } = buffer_views(buffer);
  return read_rows_from_view(
    view,
    bytes,
    metadata2,
    0,
    start,
    count,
    col_start,
    col_end,
    out,
    out_offset
  );
}

// src/strl-reader.ts
function readVariable(metadata2, index) {
  return isPackedDtaReadPlan(metadata2) ? metadata2.variable(index) : metadata2.variables[index];
}
var GSO_MARKER = [71, 83, 79];
var STRLS_TAG = "<strls>";
var STRLS_TAG_LENGTH = STRLS_TAG.length;
var ASCII_DECODER2 = new TextDecoder("utf-8");
function build_gso_index(buffer, metadata2, base_offset = 0) {
  const my_index = /* @__PURE__ */ new Map();
  const my_has_strl = isPackedDtaReadPlan(metadata2) ? metadata2.strl_columns.length > 0 : metadata2.variables.some((v) => v.type === "strL");
  if (!my_has_strl) return my_index;
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  const little_endian = metadata2.byte_order === "LSF";
  const my_section_start = metadata2.section_offsets.strls - base_offset;
  if (my_section_start < 0 || my_section_start + STRLS_TAG_LENGTH > bytes.length || ASCII_DECODER2.decode(bytes.subarray(
    my_section_start,
    my_section_start + STRLS_TAG_LENGTH
  )) !== STRLS_TAG) {
    throw new Error("Invalid <strls> section opening tag");
  }
  let pos = my_section_start + STRLS_TAG_LENGTH;
  const my_section_end = metadata2.section_offsets.value_labels - base_offset;
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
    const my_header_tail = metadata2.format_version === 117 ? 13 : 17;
    if (pos + my_header_tail > my_close_start) {
      throw new Error("Truncated GSO header");
    }
    const my_v = view.getUint32(pos, little_endian);
    pos += 4;
    let my_o;
    if (metadata2.format_version === 117) {
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
    const my_variable = readVariable(metadata2, my_v - 1);
    if (my_v < 1 || my_o < 1 || my_o > metadata2.nobs || !my_variable || my_variable.type !== "strL") {
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
function resolve_strl(buffer, metadata2, gso_index, pointer_offset) {
  const view = new DataView(buffer);
  const bytes = new Uint8Array(buffer);
  const my_pointer = read_strl_pointer(
    view,
    metadata2,
    pointer_offset
  );
  if (!my_pointer) return "";
  const my_key = my_pointer.v + ":" + my_pointer.o;
  const my_entry = gso_index.get(my_key);
  if (!my_entry) {
    throw new Error(`Dangling strL pointer ${my_key}`);
  }
  return decode_gso_entry(
    bytes,
    my_entry,
    resolve_text_encoding(
      metadata2.format_version,
      metadata2.text_encoding
    )
  );
}
function read_strl_pointer(view, metadata2, pointer_offset) {
  const little_endian = metadata2.byte_order === "LSF";
  let my_v;
  let my_o;
  if (metadata2.format_version === 117) {
    my_v = view.getUint32(
      pointer_offset,
      little_endian
    );
    my_o = view.getUint32(
      pointer_offset + 4,
      little_endian
    );
  } else if (metadata2.format_version === 118) {
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
  const my_variable = readVariable(metadata2, my_v - 1);
  if (my_v < 1 || my_o < 1 || my_o > metadata2.nobs || !my_variable || my_variable.type !== "strL") {
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
var VALUE_LABELS_CLOSE_TAG = "</value_labels>";
var VALUE_LABELS_TAG_LENGTH = VALUE_LABELS_TAG.length;
var LBL_OPEN_TAG = "<lbl>";
var MAX_VALUE_LABEL_ENTRIES = 65536;
var STRICT_UTF8 = new TextDecoder("utf-8", { fatal: true });
function is_utf8_boundary(bytes, start, end, offset) {
  if (offset === start || (bytes[offset] & 192) !== 128) return true;
  let lead = offset;
  const earliest = Math.max(start, offset - 3);
  while (lead > earliest && (bytes[lead] & 192) === 128) lead--;
  const byte = bytes[lead];
  const width = byte >= 194 && byte <= 223 ? 2 : byte >= 224 && byte <= 239 ? 3 : byte >= 240 && byte <= 244 ? 4 : 0;
  if (width === 0 || offset >= lead + width || lead + width > end) return true;
  try {
    STRICT_UTF8.decode(bytes.subarray(lead, lead + width));
    return false;
  } catch {
    return true;
  }
}
function expect_tag2(bytes, pos, tag, end) {
  if (pos + tag.length > end) throw new Error(`Truncated ${tag} tag`);
  for (let i = 0; i < tag.length; i++) {
    if (bytes[pos + i] !== tag.charCodeAt(i)) {
      throw new Error(`Expected ${tag} at offset ${pos}`);
    }
  }
  return pos + tag.length;
}
var MODERN_LABEL_NAME_WIDTH = {
  117: 33,
  118: 129,
  119: 129
};
var PADDING_BYTES = 3;
function parse_label_entry_payload(bytes, view, little_endian, pos, entry_end, decoder2, declared_length, utf8) {
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
  if (my_n > MAX_VALUE_LABEL_ENTRIES) {
    throw new Error("Corrupt value label table: entry count exceeds 65,536");
  }
  if (declared_length !== 8 + my_n * 8 + my_txt_len) {
    throw new Error("Corrupt value label table: inconsistent table length");
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
    if (utf8 && !is_utf8_boundary(
      bytes,
      my_text_start,
      my_text_start + my_txt_len,
      my_str_start
    )) {
      throw new Error("Corrupt value label table: text offset is inside a UTF-8 code point");
    }
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
      decoder2,
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
function read_label_name(bytes, pos, name_width, decoder2, require_terminator = false) {
  let my_end = pos;
  const my_limit = pos + name_width;
  while (my_end < my_limit && bytes[my_end] !== 0) {
    my_end++;
  }
  if (my_limit > bytes.length || require_terminator && my_end === my_limit) {
    throw new Error("Corrupt value label table: unterminated or truncated table name");
  }
  return decode_text_range(decoder2, bytes, pos, my_end);
}
function parse_modern_entries(bytes, view, little_endian, name_width, start_pos, section_end, decoder2, utf8) {
  const my_result = /* @__PURE__ */ new Map();
  let pos = start_pos;
  const tables_end = section_end - VALUE_LABELS_CLOSE_TAG.length;
  while (pos < tables_end) {
    pos = expect_tag2(bytes, pos, LBL_OPEN_TAG, tables_end);
    if (pos + 4 + name_width + PADDING_BYTES + 8 > tables_end) {
      throw new Error("Corrupt value label table: truncated header");
    }
    const declared_length = view.getInt32(pos, little_endian);
    pos += 4;
    const my_label_name = read_label_name(
      bytes,
      pos,
      name_width,
      decoder2,
      true
    );
    pos += name_width;
    pos += PADDING_BYTES;
    const { label_map, next_pos } = parse_label_entry_payload(
      bytes,
      view,
      little_endian,
      pos,
      tables_end,
      decoder2,
      declared_length,
      utf8
    );
    my_result.set(my_label_name, label_map);
    pos = expect_tag2(bytes, next_pos, "</lbl>", tables_end);
  }
  if (expect_tag2(bytes, pos, VALUE_LABELS_CLOSE_TAG, section_end) !== section_end) {
    throw new Error("Corrupt value label section: trailing bytes");
  }
  return my_result;
}
function parse_legacy_entries(bytes, view, little_endian, name_width, start_pos, section_end, decoder2, utf8) {
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
    if (pos + 4 + name_width + PADDING_BYTES + 8 > section_end) {
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
      decoder2
    );
    pos += name_width;
    pos += PADDING_BYTES;
    const { label_map, next_pos } = parse_label_entry_payload(
      bytes,
      view,
      little_endian,
      pos,
      section_end,
      decoder2,
      my_table_len,
      utf8
    );
    my_result.set(my_label_name, label_map);
    pos = next_pos;
  }
  return my_result;
}
function parse_fixed8_entries(bytes, view, little_endian, name_width, start_pos, section_end, decoder2) {
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
      decoder2
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
        decoder2
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
function parse_value_labels(buffer, metadata2, base_offset = 0) {
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  const little_endian = metadata2.byte_order === "LSF";
  const my_legacy = is_legacy_format(
    metadata2.format_version
  );
  const encoding = resolve_text_encoding(
    metadata2.format_version,
    metadata2.text_encoding
  );
  const my_decoder = text_decoder(encoding);
  const my_tag_skip = my_legacy ? 0 : VALUE_LABELS_TAG_LENGTH;
  const my_start_pos = metadata2.section_offsets.value_labels - base_offset + my_tag_skip;
  const my_section_end = metadata2.section_offsets.dta_data_close - base_offset;
  const section_start = metadata2.section_offsets.value_labels - base_offset;
  if (!Number.isSafeInteger(section_start) || !Number.isSafeInteger(my_section_end) || section_start < 0 || my_section_end < section_start || my_section_end > bytes.length) {
    throw new Error("Corrupt value label section: invalid bounds");
  }
  if (!my_legacy) {
    expect_tag2(bytes, section_start, VALUE_LABELS_TAG, my_section_end);
    const end = expect_tag2(bytes, my_section_end, "</stata_dta>", bytes.length);
    if (end !== bytes.length || base_offset + end !== metadata2.section_offsets.end_of_file) {
      throw new Error("Corrupt value label section: mapped file extent mismatch");
    }
  }
  if (is_legacy_format(metadata2.format_version)) {
    const my_layout = legacy_layout_for_version(
      metadata2.format_version
    );
    let my_value_label_layout = my_layout.value_label_layout;
    let my_name_width = my_layout.value_label_table_name_width;
    if (metadata2.format_version === 105 && has_variable_label_section_framing(
      bytes,
      view,
      little_endian,
      my_start_pos,
      my_section_end,
      33
    )) {
      my_value_label_layout = "offset_table";
      my_name_width = 33;
    } else if (metadata2.format_version === 108 && !has_variable_label_section_framing(
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
      my_decoder,
      encoding === "utf-8"
    );
  }
  return parse_modern_entries(
    bytes,
    view,
    little_endian,
    MODERN_LABEL_NAME_WIDTH[metadata2.format_version],
    my_start_pos,
    my_section_end,
    my_decoder,
    encoding === "utf-8"
  );
}

// src/display-format.ts
var DTA_EPOCH_YEAR = 1960;
var DTA_EPOCH_MONTH = 0;
var DTA_EPOCH_DAY = 1;
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
    DTA_EPOCH_YEAR,
    DTA_EPOCH_MONTH,
    DTA_EPOCH_DAY + days_since_epoch
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
  const my_year = DTA_EPOCH_YEAR + Math.floor(weeks_since_epoch / 52);
  let my_week = weeks_since_epoch % 52 + 1;
  if (my_week <= 0) my_week += 52;
  return `${my_year}w${my_week}`;
}
function format_tm(months_since_epoch) {
  const my_year = DTA_EPOCH_YEAR + Math.floor(months_since_epoch / 12);
  let my_month = months_since_epoch % 12 + 1;
  if (my_month <= 0) my_month += 12;
  return `${my_year}m${my_month}`;
}
function format_tq(quarters_since_epoch) {
  const my_year = DTA_EPOCH_YEAR + Math.floor(quarters_since_epoch / 4);
  let my_quarter = quarters_since_epoch % 4 + 1;
  if (my_quarter <= 0) my_quarter += 4;
  return `${my_year}q${my_quarter}`;
}
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  ArrowBuffer,
  DTA_MISSING_B,
  addStataNote,
  apply_display_format,
  build_gso_index,
  classify_missing_value,
  classify_raw_double_missing_at,
  classify_raw_float_missing,
  decode_gso_entry,
  dropStataCharacteristics,
  dropStataNotes,
  getStataCharacteristic,
  getStataNote,
  is_legacy_format,
  is_missing_value,
  is_missing_value_object,
  legacy_metadata_buffer_size,
  listStataCharacteristics,
  listStataNotes,
  make_missing_value,
  missing_type_to_label_key,
  parse_legacy_metadata,
  parse_metadata,
  parse_value_labels,
  read_rows_from_buffer,
  read_rows_from_data_buffer,
  read_strl_pointer,
  renumberStataNotes,
  resolve_strl,
  resolve_text_encoding,
  setStataCharacteristic,
  setStataNote
});
/*!
MIT License

Copyright (c) 2020 Arjun Barrett

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
