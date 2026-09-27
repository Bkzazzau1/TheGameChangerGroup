# TGCG-EMCOP

**The Game Changer Group — Election Monitoring & Collation Programme**

TGCG-EMCOP is a Flutter-based election operations platform for membership and agent accreditation, field monitoring, incident/evidence reporting, polling-unit result capture, hierarchical collation, GIS operations, communications and situation-room workflows.

## Foundation

This repository is being bootstrapped from the reusable architectural ideas in `Bkzazzau1/benuestatepdp` while deliberately removing Benue-, PDP- and candidate-specific assumptions.

Source baseline reviewed for the migration:

- Repository: `Bkzazzau1/benuestatepdp`
- Source commit: `763edba33d378804cc5555730a1d45b7f3b73a17`

The new TGCG codebase uses a national model rather than a Benue-only model.

## Core hierarchy

```text
Nigeria
  -> Geopolitical Zone
    -> State
      -> Senatorial District
        -> LGA
          -> Ward / Registration Area
            -> Polling Unit
```

## Product principles

- Offline-first field operations.
- Server-side authorization; UI visibility is never treated as authorization.
- Every operational record has stable identity, provenance and auditability.
- Election-day campaign/observer submissions remain unofficial until declared by the legally authorized election authority.
- Result evidence is preserved separately from extracted or manually entered figures.
- AI/OCR assists verification; it must not silently alter submitted figures.
- Geographic scope is explicit on users, assignments, incidents, reports and results.
- App, SMS, USSD and manual submissions are source-tagged and reconciled.

## Initial modules

1. Authentication and accreditation
2. Membership and field-agent management
3. National geography and polling-unit catalogue
4. Monitoring and incident management
5. Evidence capture
6. Result submission and verification
7. Hierarchical collation
8. Situation Room
9. Communications
10. GIS and geofencing
11. SMS/USSD fallback
12. Audit, reporting and governance

## Architecture direction

```text
Flutter clients
  -> repository contracts
    -> encrypted local storage + durable sync outbox
      -> backend APIs
        -> PostgreSQL/PostGIS
        -> Redis / queues
        -> object storage
        -> OCR / biometric services
        -> SMS / USSD gateways
```

The Flutter domain layer is kept backend-agnostic so development can begin with local implementations while preserving a clean path to production APIs and offline synchronization.
