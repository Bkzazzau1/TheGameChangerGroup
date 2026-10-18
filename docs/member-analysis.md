# Member analysis

Members & Exco shows server counts for the selected area. National Administrators can open Nigeria and drill through zones, states, LGAs, wards and polling units. Other staff retain their existing geographic access.

| View | What it measures |
| --- | --- |
| Registration growth | Registrations in the last 7 or 30 days, compared with the immediately preceding period of the same length. |
| Membership standing | Active, suspended and deactivated memberships. Identity verification is counted separately. |
| Identity | Fully verified profiles, verified profiles still missing card-related fields, awaiting review, unverified and rejected identities. These groups do not double-count members. |
| Verification source | Verified identities checked automatically, recorded on a chapter list or checked by a person. The denominator is verified members, not all registrations. |
| Account sign-in | No linked account, an account with no sign-in, last sign-in within 30 days, or an older last sign-in. The 7-day figure is a subset of the 30-day figure. This measures authentication, not ongoing app activity. |
| Missing profile fields | Missing name, VIN, card photo, selfie, gender or birth date. A member may occur in several rows. |
| Registered location | Missing state, LGA, ward or polling unit, plus polling units selected from the list. A listed unit is not assumed to match the card. |
| Area coverage | Areas with or without members or recorded exco, and members not assigned to the selected child level. No recorded exco does not imply a known vacant position. |

Clickable figures open the matching member list within the selected area. Exco counts follow the appointment's area, which may differ from the member's registered location; the exco total opens its appointment list.

The member dialog reloads the record when opened. It shows registration and verification dates, last update, registered place names/codes, positions and account sign-in. Contact and accessibility details still require the existing permission to view sensitive member data. VINs remain masked. A failed detail request does not reuse a previously cached profile.

The API additions are read-only aggregate fields under `members` in `/api/v1/members/analysis/`: `previous_7_days`, `previous_30_days`, `verification_sources`, `accounts` and `quality`. `coverage.unplaced_members` counts members without the selected child-area assignment and is zero when the area has no child breakdown. Existing endpoints and filters remain available; new analysis filters use `show=` on `/api/v1/members/`.

These changes need no migration, provider credentials or timer. They do not alter registration, verification, membership or appointment records.
