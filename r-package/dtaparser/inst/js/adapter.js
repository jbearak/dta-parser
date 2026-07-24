function dtaParserRead(input, skip, nMax) {
    const bytes = input instanceof Uint8Array
        ? input
        : new Uint8Array(input);
    const buffer = bytes.buffer.slice(
        bytes.byteOffset, bytes.byteOffset + bytes.byteLength
    );
    const metadata = [113, 114, 115].includes(bytes[0])
        ? DtaParser.parse_legacy_metadata(buffer, bytes.length)
        : DtaParser.parse_metadata(buffer);
    const start = Math.min(Math.max(0, skip || 0), metadata.nobs);
    const count = nMax < 0
        ? metadata.nobs - start
        : Math.min(nMax, metadata.nobs - start);
    const rows = DtaParser.read_rows_from_buffer(
        buffer, metadata, start, count
    );

    const strl_columns = [];
    for (let column = 0; column < metadata.variables.length; column++) {
        if (metadata.variables[column].type === "strL") {
            strl_columns.push(column);
        }
    }
    if (strl_columns.length) {
        const gso_index = DtaParser.build_gso_index(buffer, metadata);
        const data_tag_length = DtaParser.is_legacy_format(
            metadata.format_version
        ) ? 0 : 6;
        const data_start = metadata.section_offsets.data + data_tag_length;
        for (let row = 0; row < rows.length; row++) {
            for (const column of strl_columns) {
                const variable = metadata.variables[column];
                const pointer_offset = data_start
                    + (start + row) * metadata.obs_length
                    + variable.byte_offset;
                rows[row][column] = DtaParser.resolve_strl(
                    buffer, metadata, gso_index, pointer_offset
                ) || "";
            }
        }
    }

    const value_labels = DtaParser.parse_value_labels(buffer, metadata);
    const variables = metadata.variables.map(variable => {
        const table = value_labels.get(variable.value_label_name);
        return {
            name: variable.name,
            kind: variable.type.startsWith("str") ? "string" : "numeric",
            label: variable.label,
            format: variable.format,
            labels: table
                ? Array.from(table, ([value, label]) => ({ value, label }))
                : []
        };
    });
    const columns = variables.map(() => []);
    for (const row of rows) {
        for (let column = 0; column < row.length; column++) {
            columns[column].push(row[column]);
        }
    }
    return {
        dataset_label: metadata.dataset_label,
        format_version: metadata.format_version,
        nrow: rows.length,
        variables,
        columns
    };
}
