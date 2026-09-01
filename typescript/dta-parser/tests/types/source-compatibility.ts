import type {
    DtaMetadata,
    StataMetadataTarget,
    VariableInfo,
} from '../../src/index';

const oldVariable: VariableInfo = {
    name: 'x',
    type: 'byte',
    type_code: 65530,
    format: '%8.0g',
    label: '',
    value_label_name: '',
    byte_width: 1,
    byte_offset: 0,
};

const oldMetadata: DtaMetadata = {
    format_version: 118,
    byte_order: 'LSF',
    nvar: 1,
    nobs: 0,
    dataset_label: '',
    variables: [oldVariable],
    section_offsets: {
        stata_data: 0,
        map: 0,
        variable_types: 0,
        varnames: 0,
        sortlist: 0,
        formats: 0,
        value_label_names: 0,
        variable_labels: 0,
        characteristics: 0,
        data: 0,
        strls: 0,
        value_labels: 0,
        stata_data_close: 0,
        end_of_file: 0,
    },
    obs_length: 1,
};

const legacyNotes: StataMetadataTarget = {
    notes: ['first', 'second'],
};

void oldMetadata;
void legacyNotes;
