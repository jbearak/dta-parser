// What the JavaScript engine running the tests does with a NaN's
// payload (ADR 0047). V8 (Node) keeps it when a Float64Array's value is
// loaded into a number; JavaScriptCore (Bun) gives every NaN one bit
// pattern.
const f = new Float64Array(1);
const w = new Uint32Array(f.buffer);
const little = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;
w[little ? 0 : 1] = 0x7a2;
w[little ? 1 : 0] = 0x7ff00061;
const view = new DataView(new ArrayBuffer(8));
view.setFloat64(0, f[0]);

/** Whether a number keeps a NaN's payload here. */
export const nanPayloads = view.getUint32(4) === 0x7a2;

/** The engine's name, for test titles. */
export const engine = typeof Bun !== "undefined" ? "Bun" : "Node";
