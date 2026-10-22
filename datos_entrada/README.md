# Input data

`data _31025.xlsx` is the original supplied drive-test workbook, unchanged in bytes. It has 46 columns and 17,872 data rows in the supplied export. The analysis reads a subset by original column position; do not reorder columns.

The workbook contains an external Excel link. The R pipeline reads stored cell values with `readxl`; it neither updates external links nor recalculates Excel formulas. The missing linked workbook is not included. Do not claim missing source values were recovered. Rows with missing target or distance are excluded; retained numeric predictor missingness is handled inside resampling recipes.

## Fields used by the pipeline

| Original field | Role / interpretation in the code |
|---|---|
| Nodo+cellId | Cell identifier; audit only, never a predictor |
| Longitude, Latitude | Receiver coordinates; spatial blocks and audit only |
| Altura Site | Antenna height component (m) |
| ansm sitio | Site elevation component (m), as supplied |
| Altura Recep | Receiver height above vehicle/ground, fixed at 1.5 m |
| Height | Receiver elevation component (m), as supplied |
| DISTANCIA | Supplied distance, assumed metres; horizontal/3D provenance remains to be confirmed |
| BAND | L2, L28, L4; mapped to 1900, 700, 2100 MHz for descriptive plots |
| Azimut Site | Absolute antenna azimuth in degrees |
| Tilt Mec site, Tilt Elect Site | Separate mechanical and electrical tilts, in supplied units |
| Level | Received-level measurement used to construct `Perdida = 43 - Level` |

The reference value 43 dBm and measurement definition require radio-engineering documentation. This transformation is an operational target definition, not a complete independently validated link budget. Data supplied through the research collaboration with Cedrick; original collection protocol and a separate public data license were not supplied. Inclusion in this repository does not establish an open-data license.
