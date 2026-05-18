# SentryForce 2.0

SentryForce 2.0 is a Salesforce-native observability and security foundation that unifies:
- Platform Events / CDC / Event Monitoring ingestion
- Transaction Security Policies for real-time controls
- ELF retrieval workflows
- Risk scoring for threat detection patterns
- Slack-ready alerting
- Retention and compliance windows
- Lightning UI monitoring console

## What this foundation includes

### 1) Canonical event ingestion model
- `SentryEventEnvelope` defines a canonical payload for Platform Events, CDC, Event Monitoring, Lightning performance, and Apex execution telemetry.
- `SentryIngestionService` + `SentryIngestionQueueable` support asynchronous event ingestion and persistence.
- Canonical event records are stored in `Sentry_Event__c`.

### 2) Persistent storage model
- `Sentry_Event__c`: normalized event records, risk score/factors, payload, retention fields.
- `Sentry_Alert__c`: generated alerts with severity/status/channel and event linkage.
- `Sentry_Retrieval_Job__c`: ELF/event retrieval job tracking.
- `Sentry_Integration_Config__mdt`: pluggable integration config (Slack/webhook/SIEM).
- `Sentry_Retention_Policy__mdt`: retention policy definitions by event type.

### 3) Async and batch processing
- Queueable ingestion (`SentryIngestionQueueable`) for burst-safe writes.
- Batch/scheduled retention management (`SentryRetentionService.CleanupBatch`).
- Scheduled ELF retrieval service (`SentryElfRetrievalService`).

### 4) Threat detection / anomaly scoring
`SentryRiskEngine` delivers explainable scoring with factors for:
- credential stuffing patterns
- session hijacking signals
- suspicious report exports
- off-hours sensitive actions
- Lightning performance degradation
- long-running Apex + exception spikes

The scoring model is modular so ML enrichment can be added later (external feature service or Einstein integration).

### 5) Real-time transaction security controls
The repository includes flow-backed policy metadata in:
- `force-app/main/default/flows/PolicyCondition_*.flow-meta.xml`
- `force-app/main/default/transactionSecurityPolicies/*.transactionSecurityPolicy-meta.xml`

These support real-time block/alert patterns for suspicious behavior and risky actions.

### 6) Slack alert integration
`SentryAlertingService` provides pluggable alert dispatching and includes Slack webhook support via custom metadata (`Sentry_Integration_Config__mdt`).

### 7) UI monitoring console (LWC)
`force-app/main/default/lwc/sentryForceConsole` provides a Lightning console surface to:
- view recent events
- view recent alerts
- trigger ELF retrieval

Controller: `SentryMonitoringController`.

### 8) Extended data retention support
`SentryRetentionService` resolves per-event retention windows from `Sentry_Retention_Policy__mdt`, and scheduled cleanup marks aging records as compliance-archived.

### 9) Easy ELF retrieval workflows
- Apex trigger point: `SentryElfRetrievalService.startJobForRecentLogs()`
- CLI helper script: `scripts/event-monitoring/retrieve-elf.sh`

## Threat and observability use-cases covered
- Credential stuffing detection
- Session hijacking detection
- Suspicious report/export activity
- Off-hours risky access attempts
- Lightning page performance tracking
- Apex execution latency/exception tracking
- Event Monitoring/ELF retrieval and operator visibility

## Setup

### Prerequisites
- Salesforce CLI (`sf`) installed locally
- Dev Hub + target org access

### Deploy
```bash
sf project deploy start --source-dir force-app --target-org <alias>
```

### Assign policies and configure Slack
1. Update `Sentry_Integration_Config__mdt.Slack_Default` with your webhook endpoint and enable it.
2. Replace transaction security placeholder user token (`REPLACE_WITH_ADMIN_EMAIL`) in `force-app/main/default/transactionSecurityPolicies/*.transactionSecurityPolicy-meta.xml` with valid org usernames/emails.
3. Update the CI/CD user condition in `force-app/main/default/flows/PolicyCondition_AlertCriticalPermissionAs.flow-meta.xml` (`REPLACE_WITH_CICD_USERNAME`) to your environment's deployment user.
4. Update Slack endpoint token (`REPLACE_WITH_SLACK_WEBHOOK`) in `force-app/main/default/customMetadata/Sentry_Integration_Config__mdt.Slack_Default.md-meta.xml`.
5. Schedule jobs:
   - `SentryRetentionService.CleanupBatch`
   - `SentryElfRetrievalService`
6. Run pre-deploy placeholder validation:
```bash
./scripts/event-monitoring/validate-placeholders.sh
```

### Run tests
```bash
sf apex run test --test-level RunLocalTests --target-org <alias>
```

## Design lineage
This repo synthesizes implementation ideas inspired by:
- `JMurphey0317/SentryMeta1` (ops helper scripting patterns)
- `JMurphey0317/policy_sentry` and `JMurphey0317/SentryForce` (transaction security + detection concepts)
- `jongpie/NebulaLogger` (structured observability architecture mindset)
- `SeeSharpist/Nova-Salesforce-Logger` (durable event logging ideas)

SentryForce 2.0 keeps Salesforce-native runtime patterns first, with modular extension points for future ML and external SIEM integrations.
