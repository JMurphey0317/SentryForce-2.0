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

### 1) Bulkified ingestion and telemetry pipeline
- `SentryIngestionService` now chunks envelopes at 200 per transaction, aggregates actor activity once per chunk via `SentryActorActivityService`, and shares that activity map across risk evaluation.
- `SentryTelemetryService` records queue depth, queue latency, and failed queue jobs in `Sentry_Queue_Telemetry__c`.
- Canonical event records are stored in `Sentry_Event__c` with anomaly enrichment and processing latency metadata.

### 2) Correlation engine and incident layer
- `SentryCorrelationService` evaluates `Sentry_Correlation_Rule__mdt` records and creates/update `Sentry_Incident__c` plus `Sentry_Incident_Event__c` junctions.
- Sample metadata rule `Credential_Compromise` establishes the first multi-event incident pattern.
- `Sentry_Alert__c` now links alerts to incidents and supports richer workflow states.

### 3) Real-time SOC dashboard scaffolding
- `force-app/main/default/lwc/sentryDashboard` composes:
  - `sentryLiveFeed`
  - `sentryIncidentPanel`
  - `sentryThreatHeatmap`
  - `sentryMetricsCards`
  - `sentryEventTimeline`
- The dashboard includes EMP API/LMS scaffolding, telemetry panels, licensing indicators, and replay/rule foundations.
- `sentryForceConsole` now wraps the dashboard component for backward compatibility.

### 4) Secure integration architecture
- `SentryNamedCredentialService` resolves Named Credential-based endpoints from `Sentry_Integration_Config__mdt`.
- `SentryAlertingService` keeps Salesforce-native alert persistence while routing Slack notifications asynchronously and seeding SIEM deliveries into `Sentry_Connector_Delivery__c`.
- Integration metadata now supports `Integration_Type__c`, `Named_Credential__c`, `External_Credential__c`, `Path_Suffix__c`, and retry limits.

### 5) Detection rule builder foundations
- `Sentry_Detection_Rule__mdt` plus `SentryDetectionRuleService` allow metadata-driven risk adjustments.
- `sentryRuleBuilder` surfaces active rules to admins.
- `sentryRuleSimulator` calls `SentryMonitoringController.simulateDetection()` for a first working simulation slice.

### 6) Alert suppression workflows
- `Sentry_Suppression_Rule__mdt` drives duplicate, integration-user, and low-risk sandbox suppression.
- `Sentry_Alert__c.Status__c` now supports `Open → Acknowledged → Investigating → Resolved`.
- Alerts persist suppression keys and analyst assignment to support lifecycle tracking.

### 7) SIEM outbound connectors
- `SentryOutboundConnectorService` stages delivery attempts, retry counts, and dead-letter state in `Sentry_Connector_Delivery__c`.
- The connector abstraction is wired for representative connector types: Splunk, Datadog, Sentinel, Elastic, and QRadar.
- Delivery health is exposed on the SOC dashboard.

### 8) Event replay and reprocessing foundations
- `SentryReplayService` introduces `Sentry_Replay_Job__c`, batch-size throttling, progress tracking, and replay status management.
- Replayed envelopes are rehydrated from historical `Sentry_Event__c` payloads and sent back through the ingestion pipeline.
- `SentryMonitoringController.startReplay()` exposes the orchestration entry point for future UI wiring.

### 9) Detection analytics dashboards
- `SentryAnalyticsService` powers metric cards, event timeline data, and actor heatmap data for executive/reliability dashboards.
- Dashboard metrics now cover open incidents, alert backlog, average risk, and ingestion latency.
- `SentryFeatureLicenseService` adds feature availability hints for Shield, Event Monitoring, Transaction Security, CDC, and Platform Events.

### 10) ML anomaly enrichment foundations
- `SentryAnomalyEnrichmentService` adds behavioral anomaly signals for login-hour drift, API spikes, export-size spikes, and geographic changes.
- Anomaly score/factors are persisted on `Sentry_Event__c`.
- The model is enrichment-only and keeps analysts as primary decision makers.

## Threat and observability use-cases covered
- Credential stuffing detection
- Session hijacking detection
- Suspicious report/export activity
- Off-hours risky access attempts
- Lightning page performance tracking
- Apex execution latency/exception tracking
- Event Monitoring/ELF retrieval and operator visibility
- Multi-event incident correlation
- Queue latency and connector health visibility
- Replay-based detection tuning

## Setup

### Prerequisites
- Salesforce CLI (`sf`) installed locally
- Dev Hub + target org access

### Deploy
```bash
sf project deploy start --source-dir force-app --target-org <alias>
```

### Configure integrations and operations
1. Create org-specific Named Credentials / External Credentials for integrations such as `SentryForce_Slack` and grant access through your org permission model.
2. Update `Sentry_Integration_Config__mdt` records with your Named Credential, external credential, or fallback endpoint values and enable the desired channels.
3. Replace placeholder transaction security notification users (`username@company.com`) in `force-app/main/default/transactionSecurityPolicies/*.transactionSecurityPolicy-meta.xml` with valid org usernames/emails.
4. Update the CI/CD user condition in `force-app/main/default/flows/PolicyCondition_AlertCriticalPermissionAs.flow-meta.xml` (`cicd-username@company.com`) to your environment's deployment user.
5. Schedule jobs:
   - `SentryRetentionService.CleanupBatch`
   - `SentryElfRetrievalService`
   - `SentryReplayService`

### Run tests
```bash
sf apex run test --tests SentryRiskEngineTest,SentryIngestionServiceTest,SentryCorrelationServiceTest --target-org <alias>
```

