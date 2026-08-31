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
function isPackedDtaReadPlan(metadata) {
  return "variable_types" in metadata;
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
var MAX_DECODED_STATA_METADATA_VALUE_BYTES = 203352;
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
    const notes = current.map((text, index) => {
      validExistingMetadataValue(text, "note");
      return { number: index + 1, text };
    });
    target.notes = notes;
    return notes;
  }
  const numbers = /* @__PURE__ */ new Set();
  for (const note of current) {
    if (typeof note !== "object" || note === null) {
      throw new Error("Malformed Stata note metadata");
    }
    const { number, text } = note;
    if (!Number.isInteger(number) || number < 1 || number > 9999 || numbers.has(number)) {
      throw new Error("Malformed Stata note metadata");
    }
    validExistingMetadataValue(text, "note");
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
  indexes = /* @__PURE__ */ new Map();
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
  /** Scope maps retained for callers that supply un-compacted records. */
  get indexedScopeCount() {
    return this.indexes.size;
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
    const indexes = {};
    this.indexes.set(scopeIndex, indexes);
    return indexes;
  }
  noteIndexes(scopeIndex) {
    const scopeIndexes = this.scopeIndexes(scopeIndex);
    if (scopeIndexes.notes === void 0) {
      const values = mutableNotes(this.scope(scopeIndex));
      scopeIndexes.notes = {
        values,
        indices: new Map(
          values.map((note, index) => [note.number, index])
        )
      };
    }
    return scopeIndexes.notes;
  }
  characteristicIndexes(scopeIndex) {
    const scopeIndexes = this.scopeIndexes(scopeIndex);
    if (scopeIndexes.characteristics === void 0) {
      const values = mutableCharacteristics(this.scope(scopeIndex));
      scopeIndexes.characteristics = {
        values,
        indices: new Map(
          values.map((item, index) => [item.name, index])
        )
      };
    }
    return scopeIndexes.characteristics;
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
  pushLazy(target, name, value) {
    const accepted = this.accept(target, name);
    if (accepted === null) return false;
    this.pushAcceptedLazy(accepted, value);
    return true;
  }
  pushAcceptedLazy(accepted, value) {
    this.pushAccepted(accepted, value());
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
  pushAccepted(accepted, value) {
    validExistingMetadataValue(
      value,
      accepted.noteNumber === null ? "characteristic" : "note"
    );
    if (accepted.noteNumber !== null) {
      const notes = this.noteIndexes(accepted.scopeIndex);
      const existing2 = notes.indices.get(accepted.noteNumber);
      if (existing2 === void 0) {
        notes.indices.set(accepted.noteNumber, notes.values.length);
        notes.values.push({
          number: accepted.noteNumber,
          text: value
        });
      } else {
        notes.values[existing2].text = value;
      }
      return;
    }
    const characteristics = this.characteristicIndexes(
      accepted.scopeIndex
    );
    const existing = characteristics.indices.get(accepted.name);
    if (existing === void 0) {
      characteristics.indices.set(
        accepted.name,
        characteristics.values.length
      );
      characteristics.values.push({ name: accepted.name, value });
    } else {
      characteristics.values[existing].value = value;
    }
  }
  finish() {
    for (const indexes of this.indexes.values()) {
      indexes.notes?.values.sort(
        (left, right) => left.number - right.number
      );
    }
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
    this.indexes.clear();
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
function validExistingMetadataValue(value, kind) {
  if (typeof value !== "string" || value.includes("\0") || !codePointLengthAtMost(
    value,
    MAX_STATA_METADATA_VALUE_BYTES
  ) || !utf8LengthAtMost(
    value,
    MAX_DECODED_STATA_METADATA_VALUE_BYTES
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
function setStataNote(target, number, text) {
  validNoteNumber(number);
  validMetadataValue(text);
  const notes = mutableNotes(target);
  const existing = notes.find((note) => note.number === number);
  if (existing === void 0) notes.push({ number, text });
  else existing.text = text;
  notes.sort((left, right) => left.number - right.number);
}
function addStataNote(target, text) {
  const notes = mutableNotes(target);
  const number = notes.length === 0 ? 1 : Math.max(...notes.map((note) => note.number)) + 1;
  validNoteNumber(number);
  setStataNote(target, number, text);
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
function readFixedString(bytes, start, width, decoder) {
  let end = start;
  const limit = start + width;
  while (end < limit && bytes[end] !== 0) end++;
  return decoder.decode(bytes.subarray(start, end));
}
var StataCharacteristicFramePlan = class {
  constructor(bytes, decoder, collector) {
    this.bytes = bytes;
    this.decoder = decoder;
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
function parse_characteristics(bytes, view, little_endian, section_offsets, field_width, decoder, dataset, variables) {
  const collector = new StataMetadataCollector(dataset, variables);
  const plan = new StataCharacteristicFramePlan(bytes, decoder, collector);
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
function read_cell(view, bytes, offset, variable_type, byte_width, little_endian, modern_missing, decoder, format_version) {
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
        decoder
      );
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
  const packed = isPackedDtaReadPlan(metadata);
  if (my_column_count === 1) {
    const variable = packed ? metadata.variable(my_col_start) : metadata.variables[my_col_start];
    if (variable === void 0) return the_rows;
    decode_single_column_into_rows(
      view,
      bytes,
      the_rows,
      out_offset,
      my_actual_count,
      row_base_offset,
      variable,
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
      const my_variable = packed ? void 0 : metadata.variables[my_abs_col];
      const variableType = packed ? metadata.variable_types[my_abs_col] : my_variable.type;
      const byteWidth = packed ? metadata.variable_byte_widths[my_abs_col] : my_variable.byte_width;
      const byteOffset = packed ? metadata.variable_byte_offsets[my_abs_col] : my_variable.byte_offset;
      my_row[my_output_col] = read_cell(
        view,
        bytes,
        my_row_offset + byteOffset,
        variableType,
        byteWidth,
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
function read_rows_from_buffer(buffer, metadata, start, count, col_start, col_end) {
  assert_valid_row_range(start, count);
  const { view, bytes } = buffer_views(buffer);
  const my_tag_length = is_legacy_format(metadata.format_version) ? 0 : DATA_TAG_LENGTH;
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

// src/strl-reader.ts
function readVariable(metadata, index) {
  return isPackedDtaReadPlan(metadata) ? metadata.variable(index) : metadata.variables[index];
}
var GSO_MARKER = [71, 83, 79];
var STRLS_TAG = "<strls>";
var STRLS_TAG_LENGTH = STRLS_TAG.length;
var ASCII_DECODER2 = new TextDecoder("utf-8");
function build_gso_index(buffer, metadata, base_offset = 0) {
  const my_index = /* @__PURE__ */ new Map();
  const my_has_strl = isPackedDtaReadPlan(metadata) ? metadata.strl_columns.length > 0 : metadata.variables.some((v) => v.type === "strL");
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
    const my_variable = readVariable(metadata, my_v - 1);
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
  if (!my_entry) {
    throw new Error(`Dangling strL pointer ${my_key}`);
  }
  return decode_gso_entry(
    bytes,
    my_entry,
    resolve_text_encoding(
      metadata.format_version,
      metadata.text_encoding
    )
  );
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
  const my_variable = readVariable(metadata, my_v - 1);
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
export {
  STATA_MISSING_B,
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
};
