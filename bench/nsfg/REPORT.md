# NSFG conversion report

Made by `bench/nsfg/make.py` from CDC's public-use NSFG files (inventory: `inventory.json`). The .dta files are written by pandas 3.1.0 (`DataFrame.to_stata`, release 118) and are not committed.

Files listed by CDC: 139 (916.6 MB). Data files: 36; converted: 36; failed: 0. Output: 485.4 MB of .dta. Run time: 96 s.

| cycle | output | source | rows | vars | .dta size | status |
|---|---|---|---:|---:|---:|---|
| 1973 (Cycle 1) | `1973_FemResp.dta` | `1973NSFGData.dat` | 9797 | 450 | 5.7 MB | converted |
| 1976 (Cycle 2) | `1976_FemResp.dta` | `1976NSFGData.dat` | 8611 | 468 | 6.0 MB | converted |
| 1976 (Cycle 2) | `1976_Preg.dta` | `1976NSFGData.dat` | 23042 | 80 | 2.4 MB | converted |
| 1976 (Cycle 2) | `1976_PSU.dta` | `cyc2psu.sas7bdat` | 8611 | 3 | 0.0 MB | converted |
| 1982 (Cycle 3) | `1982_FemResp.dta` | `1982NSFGData.dat` | 7969 | 741 | 7.6 MB | converted |
| 1982 (Cycle 3) | `1982_Preg.dta` | `1982NSFGData.dat` | 13768 | 174 | 3.0 MB | converted |
| 1988 (Cycle 4) | `1988_FemResp.dta` | `1988FemRespData.dat` | 8450 | 1437 | 19.1 MB | converted |
| 1988 (Cycle 4) | `1988_Preg.dta` | `1988PregData.dat` | 15759 | 284 | 10.7 MB | converted |
| 1995 (Cycle 5) | `1995_FemResp.dta` | `1995FemRespData.dat` | 10847 | 5754 | 78.9 MB | converted |
| 1995 (Cycle 5) | `1995_Preg.dta` | `1995PregData.dat` | 21332 | 245 | 6.2 MB | converted |
| 2002 (Cycle 6) | `2002_FemPreg.dta` | `2002FemPreg.dat` | 13593 | 243 | 4.3 MB | converted |
| 2002 (Cycle 6) | `2002_FemResp.dta` | `2002FemResp.dat` | 7643 | 3087 | 29.3 MB | converted |
| 2002 (Cycle 6) | `2002_Male.dta` | `2002Male.dat` | 4928 | 1993 | 12.7 MB | converted |
| 2002 (Cycle 6) | `2002_HHvars.dta` | `2002HHvars.dat` | 12571 | 10 | 0.1 MB | converted |
| 2002 (Cycle 6) | `2002_curr_ins.dta` | `c6_curr_ins.sas7bdat` | 12571 | 3 | 0.1 MB | converted |
| 2002 (Cycle 6) | `2002_hhpartypnew.dta` | `hhpartypnew.sas7bdat` | 12571 | 3 | 0.1 MB | converted |
| 2006–2010 | `2006_2010_FemPreg.dta` | `2006_2010_FemPreg.dat` | 20492 | 287 | 7.6 MB | converted |
| 2006–2010 | `2006_2010_FemResp.dta` | `2006_2010_FemResp.dat` | 12279 | 3741 | 55.6 MB | converted |
| 2006–2010 | `2006_2010_Male.dta` | `2006_2010_Male.dat` | 10403 | 2801 | 37.2 MB | converted |
| 2011–2013 | `2011_2013_FemPreg.dta` | `2011_2013_FemPregData.dat` | 9543 | 278 | 3.5 MB | converted |
| 2011–2013 | `2011_2013_FemResp.dta` | `2011_2013_FemRespData.dat` | 5601 | 3094 | 22.6 MB | converted |
| 2011–2013 | `2011_2013_Male.dta` | `2011_2013_MaleData.dat` | 4815 | 3059 | 19.4 MB | converted |
| 2013–2015 | `2013_2015_FemPreg.dta` | `2013_2015_FemPregData.dat` | 9358 | 278 | 3.4 MB | converted |
| 2013–2015 | `2013_2015_FemResp.dta` | `2013_2015_FemRespData.dat` | 5699 | 3207 | 24.0 MB | converted |
| 2013–2015 | `2013_2015_Male.dta` | `2013_2015_MaleData.dat` | 4506 | 2940 | 18.0 MB | converted |
| 2015–2017 | `2015_2017_FemPreg.dta` | `2015_2017_FemPregData.dat` | 9553 | 248 | 3.0 MB | converted |
| 2015–2017 | `2015_2017_FemResp.dta` | `2015_2017_FemRespData.dat` | 5554 | 3024 | 21.7 MB | converted |
| 2015–2017 | `2015_2017_Male.dta` | `2015_2017_MaleData.dat` | 4540 | 2945 | 17.7 MB | converted |
| 2017–2019 | `2017_2019_FemPreg.dta` | `2017_2019_FemPregData.dat` | 10215 | 171 | 2.2 MB | converted |
| 2017–2019 | `2017_2019_FemResp.dta` | `2017_2019_FemRespData.dat` | 6141 | 2609 | 20.2 MB | converted |
| 2017–2019 | `2017_2019_Male.dta` | `2017_2019_MaleData.dat` | 5206 | 3009 | 20.1 MB | converted |
| 2011–2019 | `2011_2019_FemaleWgt.dta` | `2011_2019_FemaleWgtData.dat` | 22995 | 7 | 1.2 MB | converted |
| 2011–2019 | `2011_2019_MaleWgt.dta` | `2011_2019_MaleWgtData.dat` | 19067 | 7 | 1.0 MB | converted |
| 2022–2023 | `2022_2023_FemPreg.dta` | `NSFG-2022-2023-FemPregPUFData.sas7bdat` | 8247 | 111 | 1.2 MB | converted |
| 2022–2023 | `2022_2023_FemResp.dta` | `NSFG-2022-2023-FemRespPUFData.sas7bdat` | 5586 | 1912 | 13.3 MB | converted |
| 2022–2023 | `2022_2023_MaleResp.dta` | `NSFG-2022-2023-MaleRespPUFData.sas7bdat` | 4371 | 1157 | 6.3 MB | converted |

## Notes per file

- `1973_FemResp`: records are 2023 bytes; the layout ends at column 787; 9797 records have undocumented data after it, not converted; LABEL names variables INPUT does not read (the program derives them; not converted): h_finc_nlamount; layout from 1973FemRespSetup.sas (no Stata dictionary published); (INT_ID) unique.
- `1976_FemResp`: 8611 of 31653 records selected by the record type in columns 6-6; records are 1000 bytes; the layout ends at column 895; 8611 records have undocumented data after it, not converted; layout from 1976FemRespSetup.sas (no Stata dictionary published); (RESPID) unique; 83 variable labels over 80 characters cut to 80 (pandas' limit).
- `1976_Preg`: 23042 of 31653 records selected by the record type in columns 6-6; records are 1000 bytes; the layout ends at column 151; 23042 records have undocumented data after it, not converted; layout from 1976PregSetup.sas (no Stata dictionary published); (ID, BPREC1) unique.
- `1976_PSU`: (RESPID) unique.
- `1982_FemResp`: INPUT reads 2 names more than once; as in SAS the last field is kept (dropped: FMARITAL 1041-1041, AGEREMAR 1265-1267); 7969 of 21737 records selected by the record type in columns 1499-1500; layout from 1982FemRespSetup.sas (no Stata dictionary published); (CASEID) unique; 21 variable labels over 80 characters cut to 80 (pandas' limit).
- `1982_Preg`: 13768 of 21737 records selected by the record type in columns 1499-1500; layout from 1982PregSetup.sas (no Stata dictionary published); (CASEID, BPRec) unique; 9 variable labels over 80 characters cut to 80 (pandas' limit).
- `1988_FemResp`: layout from 1988FemRespSetup.sas (no Stata dictionary published); (caseid) unique; 140 variable labels over 80 characters cut to 80 (pandas' limit).
- `1988_Preg`: layout from 1988PregSetup.sas (no Stata dictionary published); (SEQNUM, PREG_NUM) unique; 18 variable labels over 80 characters cut to 80 (pandas' limit).
- `1995_FemResp`: INPUT reads 19 names more than once; as in SAS the last field is kept (dropped: FILLER 8862-8871, FILLER 8876-8885, FILLER 8890-8899, FILLER 8904-8913, FILLER 8974-8983, FILLER 9133-9142, FILLER 9147-9156, FILLER 9161-9170, FILLER 9175-9184, FILLER 9189-9198, FILLER 9203-9212, FILLER 9217-9226, FILLER 9231-9240, FILLER 9245-9254, FILLER 9259-9268, FILLER 9273-9282, FILLER 9287-9296, FILLER 9301-9310, FILLER 9315-9324); layout from 1995FemRespSetup.sas (no Stata dictionary published); (CASEID) unique; 4 variable labels over 80 characters cut to 80 (pandas' limit).
- `1995_Preg`: layout from 1995FemPregFile.sas (no Stata dictionary published); (CASEID, PREGORDR) unique.
- `2002_FemPreg`: positions agree with 2002FemPregInput.sas (243 columns); (caseid, pregordr) unique.
- `2002_FemResp`: positions agree with 2002FemRespInput.sas (3087 columns); (caseid) unique; 36 variable labels over 80 characters cut to 80 (pandas' limit).
- `2002_Male`: positions agree with 2002MaleInput.sas (1993 columns); (caseid) unique; 20 variable labels over 80 characters cut to 80 (pandas' limit).
- `2002_HHvars`: 2 PROC FORMAT entries that are ranges or non-integer keys have no Stata equivalent and were skipped; layout from 2002HHvars.SAS (no Stata dictionary published); (CASEID, R_SEX) unique.
- `2002_curr_ins`: (CASEID, R_SEX) unique; row count matches 2002curr_ins.dat.
- `2002_hhpartypnew`: (CASEID, R_SEX) unique; row count matches HHPARTYPNEWASC.DAT.
- `2006_2010_FemPreg`: positions agree with 2006_2010_FemPregSetup.sas (287 columns); (CASEID, PREGORDR) unique; 1 variable labels over 80 characters cut to 80 (pandas' limit).
- `2006_2010_FemResp`: positions agree with 2006_2010_FemRespSetup.sas (3741 columns); (CASEID) unique; 210 variable labels over 80 characters cut to 80 (pandas' limit).
- `2006_2010_Male`: positions agree with 2006_2010_MaleSetup.sas (2801 columns); (CASEID) unique; 128 variable labels over 80 characters cut to 80 (pandas' limit).
- `2011_2013_FemPreg`: positions agree with 2011_2013_FemPregSetup.sas (278 columns); (CASEID, PREGORDR) unique; 1 variable labels over 80 characters cut to 80 (pandas' limit).
- `2011_2013_FemResp`: positions agree with 2011_2013_FemRespSetup.sas (3094 columns); (CASEID) unique; 210 variable labels over 80 characters cut to 80 (pandas' limit).
- `2011_2013_Male`: positions agree with 2011_2013_MaleSetup.sas (3059 columns); (CASEID) unique; 278 variable labels over 80 characters cut to 80 (pandas' limit).
- `2013_2015_FemPreg`: positions agree with 2013_2015_FemPregSetup.sas (278 columns); (CASEID, PREGORDR) unique; 5 variable labels over 80 characters cut to 80 (pandas' limit).
- `2013_2015_FemResp`: positions agree with 2013_2015_FemRespSetup.sas (3207 columns); (CASEID) unique; 207 variable labels over 80 characters cut to 80 (pandas' limit).
- `2013_2015_Male`: positions agree with 2013_2015_MaleSetup.sas (2940 columns); (CASEID) unique; 300 variable labels over 80 characters cut to 80 (pandas' limit).
- `2015_2017_FemPreg`: positions agree with 2015_2017_FemPregSetup.sas (248 columns); (CASEID, PREGORDR) unique; 5 variable labels over 80 characters cut to 80 (pandas' limit).
- `2015_2017_FemResp`: positions agree with 2015_2017_FemRespSetup.sas (3024 columns); (CASEID) unique; 214 variable labels over 80 characters cut to 80 (pandas' limit).
- `2015_2017_Male`: positions agree with 2015_2017_MaleSetup.sas (2945 columns); (CASEID) unique; 326 variable labels over 80 characters cut to 80 (pandas' limit).
- `2017_2019_FemPreg`: positions agree with 2017_2019_FemPregSetup.sas (171 columns); (caseid, pregordr) unique; 11 variable labels over 80 characters cut to 80 (pandas' limit).
- `2017_2019_FemResp`: positions agree with 2017_2019_FemRespSetup.sas (2609 columns); (caseid) unique; 233 variable labels over 80 characters cut to 80 (pandas' limit).
- `2017_2019_Male`: positions agree with 2017_2019_MaleSetup.sas (3009 columns); (caseid) unique; 425 variable labels over 80 characters cut to 80 (pandas' limit).
- `2011_2019_FemaleWgt`: positions agree with 2011_2019_FemaleWgtSetup.sas (7 columns); (caseid) unique.
- `2011_2019_MaleWgt`: positions agree with 2011_2019_MaleWgtSetup.sas (7 columns); (caseid) unique.
- `2022_2023_FemPreg`: (CaseID, PREGORDR) unique; row count matches NSFG_2022_2023_FemPregPUFData.csv; 4 variable labels over 80 characters cut to 80 (pandas' limit).
- `2022_2023_FemResp`: (CaseID) unique; row count matches NSFG_2022_2023_FemRespPUFData.csv; 299 variable labels over 80 characters cut to 80 (pandas' limit).
- `2022_2023_MaleResp`: (CaseID) unique; row count matches NSFG_2022_2023_MaleRespPUFData.csv; 144 variable labels over 80 characters cut to 80 (pandas' limit).

## Listed but not converted

- `Datasets/NSFG/.cache`: zero-byte server artifact (the listing shows it; fetching it gives 404); not data.
- `Datasets/NSFG/.cache+`: zero-byte server artifact (the listing shows it; fetching it gives 404); not data.
- `Datasets/NSFG/2002curr_ins.dat`: fixed-width copy of c6_curr_ins.sas7bdat, with no layout program; the sas7bdat is converted and its row count is checked against this file.
- `Datasets/NSFG/C5FieldworkData.asc`: a Cycle 5 (1995) fieldwork file, by its name: 14,000 fixed-width records with no layout anywhere in CDC's directories (no .dct, SAS or SPSS program names it), so its columns cannot be named.
- `Datasets/NSFG/HHPARTYPNEWASC.DAT`: fixed-width copy of hhpartypnew.sas7bdat, with no layout program; the sas7bdat is converted and its row count is checked against this file.
- `nsfg/NSFG-2022-2023-FemPregPUFData.zip`: CSV copy of the matching sas7bdat (converted from that); its row count is checked against the sas7bdat.
- `nsfg/NSFG-2022-2023-FemRespPUFData.zip`: CSV copy of the matching sas7bdat (converted from that); its row count is checked against the sas7bdat.
- `nsfg/NSFG-2022-2023-MaleRespPUFData.zip`: CSV copy of the matching sas7bdat (converted from that); its row count is checked against the sas7bdat.
- `nsfg/NSFG-2022-2023-PUFData-SASFiles.zip`: a zip of the three 2022–2023 sas7bdat files that are also published unzipped (converted from those).
- `Datasets/NSFG/spss/*.sps`: SPSS programs; listed only, the Stata and SAS programs give the same layouts.
- Stata `.dct`/`.do` and SAS programs: dictionaries, used to read the data files above.
