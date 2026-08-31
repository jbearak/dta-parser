import type { DtaMetadata } from './types';
import type { TextEncodingOptions } from './text-encoding';
/** Return the mapped byte boundary needed for a complete modern metadata read. */
export declare function modern_metadata_buffer_size(buffer: ArrayBuffer, options?: TextEncodingOptions): number;
export declare function parse_metadata(buffer: ArrayBuffer, options?: TextEncodingOptions): DtaMetadata;
//# sourceMappingURL=header.d.ts.map