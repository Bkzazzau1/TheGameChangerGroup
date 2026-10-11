# Map data

| Folder | Contents | Source and licence |
|---|---|---|
| `nigeria_states.json` | 36 states and FCT | GRID3 / geoBoundaries ADM1, CC BY 4.0 |
| `lga/{STATE}.json` | 774 LGAs, keyed by canonical LGA code | GRID3 / geoBoundaries ADM2, CC BY 4.0 |
| `ward/{LGA}.json` | Every INEC ward in the LGA with its polling unit count, plus a boundary where available | Ward boundaries: [GRID3 NGA Operational Wards v3.0](https://data.humdata.org/dataset/grid3-nga-operational-wards-v3-0) (CIESIN, Columbia University, 2026), **CC BY-SA**. Ward names, codes and polling unit counts: INEC (see the backend's `apps/geography/data/README.md`) |

## Ward files

- Wards are keyed by INEC ward code (`18-23-01`). Every ward has `name` and
  `pus` (its number of polling units). Wards with a published boundary also
  have `label` and `rings`.
- **Coverage:** GRID3 v3.0 publishes ward boundaries for 24 states (Abia,
  Adamawa, Bauchi, Bayelsa, Borno, Delta, Enugu, FCT, Gombe, Jigawa, Kaduna,
  Kano, Katsina, Kebbi, Kogi, Kwara, Nasarawa, Niger, Ogun, Osun, Oyo, Sokoto,
  Yobe and Zamfara). The other 13 states have polling unit counts but no ward
  shapes yet.
- **Matching:** GRID3 boundaries were matched to INEC wards by state, LGA and
  name. The rules were: exact name or alternative name, then a close fuzzy
  match, then one half of joined INEC names ("TOTORO/SOKORI"). Numbered
  operational parts ("Totoro 1" to "Totoro 4") were merged into their INEC
  ward. Result: 5,295 of 5,630 INEC wards in the covered states have a
  boundary. 98.5% of ward label points fall inside their LGA, and the rest are
  border and riverine differences between the two sources.
- **Accuracy:** GRID3 states that these boundaries are operational and not yet
  fully validated by government.
- **Share-alike:** GRID3's licence requires that redistributed ward boundary
  data stays under CC BY-SA.
