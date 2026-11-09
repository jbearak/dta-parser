// @jbearak/datakit: data preparation that keeps Stata's labels and .a to
// .z, in TypeScript (plan 0021). Parquet files, fixed-width text through
// a SAS setup file, and whole tables in memory as a `Dataset`. This entry
// uses no Node API, so it runs in browsers and webviews; the functions
// that take paths are in `@jbearak/datakit/node`.

export { AsyncParquetReader, ParquetReader, openParquet, openParquetAsync, toDate, writeParquet, writeParquetTo } from "./parquet";
export type { ColumnChunk, ParquetInfo, ParquetOptions, ParquetVariable, ParquetWriteOptions, RowGroup, Statistic } from "./parquet";
export { readDataset, readDatasetAsync } from "./dataset";
export type { ReadDatasetOptions } from "./dataset";
export { convertFixedWidth } from "./fixed-width";
export type { FixedWidthOptions } from "./fixed-width";
export type { Dataset, DatasetVariable, ReadDataset, ReadVariable } from "./types";

// dta-parser's values, keys and formatting, from its wasm-free entry: the
// same objects and functions as `@jbearak/dta-parser` exports.
export { MISSING, NA, dtaKey, dtaKeys, formatValue, isMissing, isTaggedNa, missingCode, missingValue, naTag, taggedNa } from "@jbearak/dta-parser/format";
export type { Cell, Missing, MissingName, ValueLabels } from "@jbearak/dta-parser/format";
export type {
  AsyncTableReader,
  BigIntColumn,
  Characteristic,
  Column,
  DictionaryColumn,
  DtaError,
  ErrorCode,
  NumberColumn,
  ReadAt,
  ReadRange,
  StringColumn,
  TableCell,
  TableColumn,
  TableInfo,
  TableReader,
  Variable,
} from "@jbearak/dta-parser";

import { fixedWidth, freeBytes, giveMemoryBack, putBytes } from "./wasm";
import { fixedWidthMode, setupBytes } from "./fixed-width";

/**
 * For `@jbearak/datakit/node` only, which shares this entry's module
 * instance: the fixed-width calls that take module memory. Not part of
 * the API. @internal
 */
export const _internal = { fixedWidth, fixedWidthMode, freeBytes, giveMemoryBack, putBytes, setupBytes };
