// esbuild's binary loader turns a .wasm import into its bytes.
declare module "*.wasm" {
  const bytes: Uint8Array<ArrayBuffer>;
  export default bytes;
}
