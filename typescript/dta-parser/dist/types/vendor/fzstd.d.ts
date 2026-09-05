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
/**
 * Codes for errors generated within this library
 */
export declare const ZstdErrorCode: {
    readonly InvalidData: 0;
    readonly WindowSizeTooLarge: 1;
    readonly InvalidBlockType: 2;
    readonly FSEAccuracyTooHigh: 3;
    readonly DistanceTooFarBack: 4;
    readonly UnexpectedEOF: 5;
};
type ZEC = (typeof ZstdErrorCode)[keyof typeof ZstdErrorCode];
/**
 * An error generated within this library
 */
export interface ZstdError extends Error {
    /**
     * The code associated with this error
     */
    code: ZEC;
}
/** Decode one frame into bounded caller-owned storage. Checksums are verified by the adapter. */
export declare function decompressFrame(dat: Uint8Array, out: Uint8Array): {
    written: any;
    consumed: any;
    checksumOffset: any;
};
export {};
//# sourceMappingURL=fzstd.d.ts.map