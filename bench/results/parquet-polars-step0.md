# Plan 0019 step 0: the spike's Arrow path before PR 2a

The spike branch's (3ec678a) matrix, rerun with its own build before any PR 2a change: four files, each as Parquet from our writer, pyarrow and polars; ours at its defaults and at the spike's tuned settings (`ours-t16-v4-lazy-w4`), polars, and pyarrow. Each cell: wall ms / CPU ms / peak RSS MiB, medians of five fresh processes. Load average 9 to 24.

| file | writer | task | ours (default) | ours tuned | polars | pyarrow |
|---|---|---|---|---|---|---|
| DHS Tajikistan 2017 wm | ours | full | 53.1 / 87.6 / 404 | 25.7 / 114.5 / 415 | 24.6 / 70.8 / 360 | 222.3 / 390.5 / 445 |
| DHS Tajikistan 2017 wm | ours | five | 4.9 / 4.9 / 68 | 5.1 / 5.3 / 68 | 6.7 / 11.8 / 93 | 173.0 / 173.7 / 133 |
| DHS Tajikistan 2017 wm | ours | window | 21.8 / 29.4 / 116 | 17.1 / 41.3 / 124 | 15.2 / 32.7 / 129 | 245.6 / 403.8 / 448 |
| DHS Tajikistan 2017 wm | ours | pass | 92.8 / 152.8 / 455 | 66.0 / 174.6 / 467 | 60.3 / 120.8 / 396 | 293.3 / 440.3 / 446 |
| DHS Tajikistan 2017 wm | pyarrow | full | 49.2 / 84.1 / 396 | 24.0 / 112.6 / 410 | 24.7 / 71.6 / 358 | 232.6 / 405.6 / 446 |
| DHS Tajikistan 2017 wm | pyarrow | five | 3.6 / 3.6 / 66 | 3.8 / 4.0 / 66 | 6.6 / 12.0 / 90 | 187.7 / 188.6 / 131 |
| DHS Tajikistan 2017 wm | pyarrow | window | 19.5 / 29.8 / 109 | 15.3 / 44.3 / 123 | 15.4 / 34.9 / 128 | 235.8 / 411.6 / 446 |
| DHS Tajikistan 2017 wm | pyarrow | pass | 89.6 / 153.3 / 449 | 62.8 / 179.2 / 464 | 60.6 / 127.9 / 396 | 299.2 / 473.0 / 444 |
| DHS Tajikistan 2017 wm | polars | full | 50.9 / 87.6 / 395 | 23.4 / 115.4 / 412 | 25.9 / 74.8 / 358 | 234.5 / 416.9 / 444 |
| DHS Tajikistan 2017 wm | polars | five | 3.4 / 3.4 / 66 | 3.6 / 3.9 / 66 | 6.8 / 11.5 / 91 | 177.3 / 178.1 / 129 |
| DHS Tajikistan 2017 wm | polars | window | 19.7 / 30.2 / 109 | 14.2 / 44.8 / 124 | 15.4 / 37.5 / 126 | 236.4 / 424.4 / 446 |
| DHS Tajikistan 2017 wm | polars | pass | 91.9 / 157.1 / 448 | 66.3 / 181.8 / 464 | 67.6 / 136.6 / 396 | 301.1 / 488.7 / 445 |
| NSFG 2002 FemResp | ours | full | 34.2 / 51.9 / 205 | 22.2 / 58.0 / 212 | 29.7 / 45.2 / 197 | 226.1 / 309.2 / 292 |
| NSFG 2002 FemResp | ours | five | 4.0 / 4.0 / 67 | 5.4 / 4.6 / 67 | 9.4 / 9.0 / 89 | 197.4 / 195.9 / 128 |
| NSFG 2002 FemResp | ours | window | 21.6 / 21.4 / 97 | 22.9 / 21.5 / 91 | 21.3 / 28.8 / 110 | 255.3 / 308.1 / 300 |
| NSFG 2002 FemResp | ours | pass | 79.5 / 86.5 / 239 | 51.8 / 106.0 / 240 | 49.8 / 86.2 / 219 | 268.0 / 350.1 / 297 |
| NSFG 2002 FemResp | pyarrow | full | 28.1 / 42.0 / 194 | 17.7 / 54.0 / 208 | 26.1 / 35.9 / 194 | 239.3 / 314.5 / 296 |
| NSFG 2002 FemResp | pyarrow | five | 2.7 / 2.7 / 64 | 3.4 / 3.4 / 64 | 6.9 / 8.5 / 85 | 189.3 / 189.7 / 123 |
| NSFG 2002 FemResp | pyarrow | window | 16.3 / 16.3 / 88 | 17.5 / 20.3 / 87 | 19.8 / 24.8 / 106 | 223.0 / 311.7 / 289 |
| NSFG 2002 FemResp | pyarrow | pass | 51.4 / 87.3 / 231 | 41.7 / 99.7 / 246 | 45.9 / 77.1 / 220 | 234.9 / 335.7 / 284 |
| NSFG 2002 FemResp | polars | full | 28.0 / 44.6 / 194 | 16.3 / 57.5 / 209 | 25.1 / 37.9 / 193 | 200.2 / 320.3 / 282 |
| NSFG 2002 FemResp | polars | five | 2.4 / 2.4 / 64 | 2.6 / 2.8 / 64 | 4.6 / 9.7 / 86 | 172.1 / 172.8 / 122 |
| NSFG 2002 FemResp | polars | window | 20.0 / 20.0 / 87 | 20.5 / 23.0 / 87 | 16.0 / 25.9 / 105 | 204.0 / 318.4 / 284 |
| NSFG 2002 FemResp | polars | pass | 53.9 / 93.4 / 231 | 45.6 / 107.7 / 242 | 49.1 / 83.9 / 219 | 239.7 / 360.6 / 285 |
| long | ours | full | 119.2 / 478.5 / 1092 | 65.8 / 524.1 / 1228 | 55.3 / 444.9 / 1260 | 253.1 / 774.9 / 1673 |
| long | ours | five | 135.7 / 304.1 / 539 | 49.0 / 345.1 / 750 | 44.0 / 244.4 / 792 | 222.3 / 529.2 / 792 |
| long | ours | window | 2.3 / 2.3 / 66 | 2.4 / 2.6 / 65 | 4.0 / 9.7 / 94 | 241.2 / 767.2 / 1673 |
| long | ours | pass | 115.2 / 484.6 / 1357 | 73.1 / 578.2 / 1506 | 61.5 / 451.2 / 1466 | 280.2 / 817.8 / 1714 |
| long | pyarrow | full | 121.8 / 478.7 / 1200 | 71.4 / 558.6 / 1478 | 73.6 / 420.7 / 1317 | 283.9 / 714.5 / 1737 |
| long | pyarrow | five | 125.7 / 273.7 / 656 | 50.5 / 360.5 / 922 | 41.6 / 255.1 / 701 | 246.1 / 446.8 / 838 |
| long | pyarrow | window | 5.5 / 5.5 / 68 | 5.7 / 6.0 / 67 | 8.7 / 19.6 / 146 | 289.7 / 719.9 / 1751 |
| long | pyarrow | pass | 151.6 / 580.8 / 1494 | 99.3 / 682.2 / 1775 | 110.0 / 515.4 / 1414 | 343.5 / 766.0 / 1841 |
| long | polars | full | 188.4 / 819.0 / 1068 | 87.6 / 900.5 / 1160 | 86.3 / 837.8 / 1276 | 292.8 / 1173 / 1765 |
| long | polars | five | 209.3 / 448.1 / 525 | 65.2 / 490.6 / 671 | 74.8 / 450.5 / 768 | 247.5 / 672.6 / 820 |
| long | polars | window | 6.6 / 6.6 / 64 | 6.8 / 7.1 / 65 | 9.1 / 13.9 / 87 | 279.0 / 1182 / 1767 |
| long | polars | pass | 239.8 / 944.4 / 1373 | 145.3 / 1036 / 1435 | 129.6 / 1035 / 1508 | 370.8 / 1208 / 1813 |
| groups | ours | full | 76.6 / 121.1 / 375 | 28.6 / 153.5 / 464 | 17.6 / 70.8 / 406 | 219.1 / 436.8 / 654 |
| groups | ours | five | 51.1 / 121.8 / 375 | 26.4 / 150.1 / 469 | 16.6 / 73.6 / 406 | 232.3 / 437.4 / 641 |
| groups | ours | window | 0.9 / 0.9 / 62 | 1.5 / 1.3 / 62 | 15.8 / 5.2 / 78 | 322.3 / 440.2 / 640 |
| groups | ours | pass | 311.1 / 163.1 / 558 | 76.4 / 187.9 / 650 | 29.9 / 102.8 / 576 | 447.6 / 474.7 / 752 |
| groups | pyarrow | full | 64.4 / 132.3 / 379 | 29.7 / 149.6 / 437 | 16.3 / 73.7 / 394 | 247.5 / 388.6 / 607 |
| groups | pyarrow | five | 46.4 / 115.3 / 379 | 30.3 / 152.4 / 433 | 17.5 / 74.9 / 395 | 247.6 / 395.6 / 610 |
| groups | pyarrow | window | 0.5 / 0.5 / 60 | 0.7 / 1.0 / 61 | 2.4 / 7.4 / 78 | 248.5 / 393.6 / 603 |
| groups | pyarrow | pass | 53.9 / 135.6 / 561 | 36.7 / 181.7 / 616 | 26.2 / 113.4 / 571 | 275.2 / 409.6 / 701 |
| groups | polars | full | 43.7 / 105.8 / 370 | 20.6 / 151.0 / 438 | 14.0 / 81.7 / 410 | 199.5 / 451.6 / 668 |
| groups | polars | five | 43.5 / 103.3 / 370 | 19.8 / 143.8 / 445 | 15.1 / 84.8 / 411 | 196.3 / 450.7 / 669 |
| groups | polars | window | 0.6 / 0.6 / 62 | 0.7 / 0.9 / 61 | 2.0 / 7.2 / 77 | 197.5 / 463.4 / 669 |
| groups | polars | pass | 54.1 / 133.4 / 553 | 31.1 / 183.4 / 615 | 23.9 / 112.0 / 586 | 233.0 / 471.8 / 787 |

### ours (default) against polars
geometric means of ours/theirs over the 4 files x 3 writers (wall, RSS, CPU): full 2.03, 0.98, 1.24; five 1.22, 0.79, 0.65; window 0.60, 0.78, 0.37; pass 1.83, 1.03, 1.15
42 target 2/3 misses:
- 2 wall full ours DHS Tajikistan 2017 wm: 53.1 vs 24.6 ms (2.16x)
- 3 CPU full ours DHS Tajikistan 2017 wm: 87.6 vs 70.8 ms, speedup 0.46
- 2 wall full ours long: 119.2 vs 55.3 ms (2.16x)
- 2 wall full ours groups: 76.6 vs 17.6 ms (4.34x)
- 3 CPU full ours groups: 121.1 vs 70.8 ms, speedup 0.23
- 2 wall full pyarrow DHS Tajikistan 2017 wm: 49.2 vs 24.7 ms (1.99x)
- 3 CPU full pyarrow DHS Tajikistan 2017 wm: 84.1 vs 71.6 ms, speedup 0.50
- 3 CPU full pyarrow NSFG 2002 FemResp: 42.0 vs 35.9 ms, speedup 0.93
- 2 wall full pyarrow long: 121.8 vs 73.6 ms (1.65x)
- 2 wall full pyarrow groups: 64.4 vs 16.3 ms (3.95x)
- 3 CPU full pyarrow groups: 132.3 vs 73.7 ms, speedup 0.25
- 2 wall full polars DHS Tajikistan 2017 wm: 50.9 vs 25.9 ms (1.96x)
- 3 CPU full polars DHS Tajikistan 2017 wm: 87.6 vs 74.8 ms, speedup 0.51
- 3 CPU full polars NSFG 2002 FemResp: 44.6 vs 37.9 ms, speedup 0.90
- 2 wall full polars long: 188.4 vs 86.3 ms (2.18x)
- 2 wall full polars groups: 43.7 vs 14.0 ms (3.11x)
- 3 CPU full polars groups: 105.8 vs 81.7 ms, speedup 0.32
- 2 wall five ours long: 135.7 vs 44.0 ms (3.09x)
- 3 CPU five ours long: 304.1 vs 244.4 ms, speedup 0.32
- 2 wall five ours groups: 51.1 vs 16.6 ms (3.08x)
- 3 CPU five ours groups: 121.8 vs 73.6 ms, speedup 0.32
- 2 wall five pyarrow long: 125.7 vs 41.6 ms (3.02x)
- 2 wall five pyarrow groups: 46.4 vs 17.5 ms (2.65x)
- 3 CPU five pyarrow groups: 115.3 vs 74.9 ms, speedup 0.38
- 2 wall five polars long: 209.3 vs 74.8 ms (2.80x)
- 2 wall five polars groups: 43.5 vs 15.1 ms (2.88x)
- 3 CPU five polars groups: 103.3 vs 84.8 ms, speedup 0.35
- 2 wall pass ours DHS Tajikistan 2017 wm: 92.8 vs 60.3 ms (1.54x)
- 3 CPU pass ours DHS Tajikistan 2017 wm: 152.8 vs 120.8 ms, speedup 0.65
- 2 wall pass ours NSFG 2002 FemResp: 79.5 vs 49.8 ms (1.59x)
- 2 wall pass ours long: 115.2 vs 61.5 ms (1.87x)
- 2 wall pass ours groups: 311.1 vs 29.9 ms (10.40x)
- 3 CPU pass ours groups: 163.1 vs 102.8 ms, speedup 0.10
- 2 wall pass pyarrow DHS Tajikistan 2017 wm: 89.6 vs 60.6 ms (1.48x)
- 3 CPU pass pyarrow DHS Tajikistan 2017 wm: 153.3 vs 127.9 ms, speedup 0.68
- 2 wall pass pyarrow long: 151.6 vs 110.0 ms (1.38x)
- 2 wall pass pyarrow groups: 53.9 vs 26.2 ms (2.06x)
- 3 CPU pass pyarrow groups: 135.6 vs 113.4 ms, speedup 0.49
- 2 wall pass polars DHS Tajikistan 2017 wm: 91.9 vs 67.6 ms (1.36x)
- 2 wall pass polars long: 239.8 vs 129.6 ms (1.85x)
- 2 wall pass polars groups: 54.1 vs 23.9 ms (2.26x)
- 3 CPU pass polars groups: 133.4 vs 112.0 ms, speedup 0.44

### ours (default) against pyarrow
geometric means of ours/theirs over the 4 files x 3 writers (wall, RSS, CPU): full 0.25, 0.69, 0.28; five 0.08, 0.57, 0.09; window 0.02, 0.13, 0.01; pass 0.33, 0.83, 0.37
0 target 2/3 misses:

### ours tuned against polars
geometric means of ours/theirs over the 4 files x 3 writers (wall, RSS, CPU): full 1.04, 1.08, 1.52; five 0.86, 0.89, 0.77; window 0.62, 0.79, 0.49; pass 1.15, 1.11, 1.37
31 target 2/3 misses:
- 3 CPU full ours DHS Tajikistan 2017 wm: 114.5 vs 70.8 ms, speedup 0.96
- 3 CPU full ours long: 524.1 vs 444.9 ms, speedup 0.84
- 3 CPU full ours groups: 153.5 vs 70.8 ms, speedup 0.62
- 3 CPU full pyarrow DHS Tajikistan 2017 wm: 112.6 vs 71.6 ms, speedup 1.03
- 3 CPU full pyarrow NSFG 2002 FemResp: 54.0 vs 35.9 ms, speedup 1.48
- 3 CPU full pyarrow long: 558.6 vs 420.7 ms, speedup 1.03
- 3 CPU full pyarrow groups: 149.6 vs 73.7 ms, speedup 0.55
- 3 CPU full polars DHS Tajikistan 2017 wm: 115.4 vs 74.8 ms, speedup 1.11
- 3 CPU full polars groups: 151.0 vs 81.7 ms, speedup 0.68
- 3 CPU five ours long: 345.1 vs 244.4 ms, speedup 0.90
- 3 CPU five ours groups: 150.1 vs 73.6 ms, speedup 0.63
- 2 RSS five pyarrow long: 922 vs 701 MiB (1.32x)
- 3 CPU five pyarrow long: 360.5 vs 255.1 ms, speedup 0.82
- 3 CPU five pyarrow groups: 152.4 vs 74.9 ms, speedup 0.58
- 3 CPU five polars groups: 143.8 vs 84.8 ms, speedup 0.76
- 3 CPU window ours DHS Tajikistan 2017 wm: 41.3 vs 32.7 ms, speedup 0.89
- 3 CPU window pyarrow DHS Tajikistan 2017 wm: 44.3 vs 34.9 ms, speedup 1.01
- 3 CPU window polars DHS Tajikistan 2017 wm: 44.8 vs 37.5 ms, speedup 1.09
- 3 CPU pass ours DHS Tajikistan 2017 wm: 174.6 vs 120.8 ms, speedup 0.91
- 3 CPU pass ours NSFG 2002 FemResp: 106.0 vs 86.2 ms, speedup 0.96
- 3 CPU pass ours long: 578.2 vs 451.2 ms, speedup 0.84
- 2 wall pass ours groups: 76.4 vs 29.9 ms (2.55x)
- 3 CPU pass ours groups: 187.9 vs 102.8 ms, speedup 0.39
- 3 CPU pass pyarrow DHS Tajikistan 2017 wm: 179.2 vs 127.9 ms, speedup 0.96
- 3 CPU pass pyarrow NSFG 2002 FemResp: 99.7 vs 77.1 ms, speedup 1.10
- 2 RSS pass pyarrow long: 1775 vs 1414 MiB (1.26x)
- 3 CPU pass pyarrow long: 682.2 vs 515.4 ms, speedup 1.11
- 3 CPU pass pyarrow groups: 181.7 vs 113.4 ms, speedup 0.71
- 3 CPU pass polars DHS Tajikistan 2017 wm: 181.8 vs 136.6 ms, speedup 1.02
- 3 CPU pass polars NSFG 2002 FemResp: 107.7 vs 83.9 ms, speedup 1.08
- 3 CPU pass polars groups: 183.4 vs 112.0 ms, speedup 0.77

### ours tuned against pyarrow
geometric means of ours/theirs over the 4 files x 3 writers (wall, RSS, CPU): full 0.13, 0.77, 0.34; five 0.06, 0.65, 0.10; window 0.02, 0.13, 0.02; pass 0.21, 0.90, 0.44
0 target 2/3 misses:

| file | variant | open | setup | read | (text on calling thread) | bitmaps | polars import | total |
|---|---|---|---|---|---|---|---|---|
| DHS Tajikistan 2017 wm | ours (default) | 6.5 | 4.4 | 34.9 | 0.2 | 3.7 | 2.7 | 53.1 |
| DHS Tajikistan 2017 wm | ours tuned | 5.0 | 4.5 | 10.4 | 0.0 | 2.4 | 2.7 | 25.7 |
| NSFG 2002 FemResp | ours (default) | 6.4 | 6.1 | 17.8 | 0.1 | 1.5 | 1.7 | 34.2 |
| NSFG 2002 FemResp | ours tuned | 3.7 | 8.7 | 6.4 | 0.0 | 1.2 | 1.7 | 22.2 |
| long | ours (default) | 0.3 | 0.0 | 117.1 | 63.9 | 1.6 | 0.2 | 119.2 |
| long | ours tuned | 0.3 | 0.0 | 64.1 | 0.1 | 1.1 | 0.2 | 65.8 |
| groups | ours (default) | 0.2 | 0.0 | 74.0 | 31.9 | 2.1 | 0.3 | 76.6 |
| groups | ours tuned | 0.2 | 0.0 | 26.6 | 0.0 | 1.6 | 0.2 | 28.6 |

| file | writer | task | one batch | one batch per row group (chunks) |
|---|---|---|---|---|
| long | ours | full | 65.8 / 524.1 / 1228 | 63.0 / 516.6 / 1228 (39) |
| long | ours | pass | 73.1 / 578.2 / 1506 | 83.7 / 629.4 / 1538 (39) |
| long | pyarrow | full | 71.4 / 558.6 / 1478 | 78.5 / 565.4 / 1482 (10) |
| long | pyarrow | pass | 99.3 / 682.2 / 1775 | 80.5 / 643.9 / 1780 (10) |
| long | polars | full | 87.6 / 900.5 / 1160 | 140.1 / 904.0 / 1165 (77) |
| long | polars | pass | 145.3 / 1036 / 1435 | 167.6 / 1064 / 1453 (77) |
| groups | ours | full | 28.6 / 153.5 / 464 | 36.4 / 142.7 / 467 (58) |
| groups | ours | pass | 76.4 / 187.9 / 650 | 48.5 / 177.0 / 648 (58) |
| groups | pyarrow | full | 29.7 / 149.6 / 437 | 27.8 / 148.5 / 436 (15) |
| groups | pyarrow | pass | 36.7 / 181.7 / 616 | 41.9 / 190.3 / 618 (15) |
| groups | polars | full | 20.6 / 151.0 / 438 | 24.5 / 153.9 / 440 (115) |
| groups | polars | pass | 31.1 / 183.4 / 615 | 35.0 / 189.0 / 628 (115) |

data held (MiB):  {'dhs-tajikistan-2017-wm': 219, 'nsfg-2002_FemResp': 93, 'long': 956, 'groups': 288} polars est (MiB): {'dhs-tajikistan-2017-wm': 218, 'nsfg-2002_FemResp': 92, 'long': 782, 'groups': 302} base RSS (MiB): {'ours': 58, 'polars': 58, 'pyarrow': 58}
load: min 12.1 median 16.4 max 32.0; spread median 0.10 max 12.35
pass checksums (missing counts) agree across libraries: True
