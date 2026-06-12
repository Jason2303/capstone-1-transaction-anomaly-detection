# Threat Model — Transaction Anomaly Detection Pipeline

## Overview

This document applies the STRIDE threat modelling framework to the Transaction Anomaly Detection Pipeline. The pipeline ingests payment transaction events, detects anomalies, and fires real-time alerts. It handles financial data and audit logs, making confidentiality, integrity, and auditability primary security concerns.

---

## Architecture Summary

```
Lambda1 (Ingestion Simulator) → EventBridge → Lambda2 (Detector) ↔ DynamoDB
                                                      ↓
                                                     SNS → Email
                                                      ↓
                                             SQS Dead Letter Queue

CloudTrail → S3 + CloudWatch Logs
All services → KMS Customer Managed Key
```

---

## Assets

| Asset | Classification | Sensitivity |
|-------|---------------|-------------|
| Transaction event data (amounts, accounts, beneficiaries) | Confidential | High |
| DynamoDB transaction records | Confidential | High |
| SNS alert emails | Internal | Medium |
| CloudTrail audit logs | Internal | High |
| KMS Customer Managed Key | Critical | Critical |
| IAM execution roles and policies | Internal | High |
| Terraform state file | Internal | High |

---

## Trust Boundaries

1. **External → AWS** — the mock JSON file simulates an external payment processor. In production, this boundary would be between the bank's payment gateway and the ingestion layer.
2. **Lambda1 → EventBridge** — Lambda1 crosses into the event bus. EventBridge enforces source and detail-type filtering.
3. **EventBridge → Lambda2** — EventBridge invokes Lambda2 with IAM-controlled permissions.
4. **Lambda2 → DynamoDB / SNS** — Lambda2 interacts with downstream services under least-privilege IAM roles.
5. **CloudTrail → S3 / CloudWatch** — CloudTrail writes audit logs under a dedicated IAM role.

---

## STRIDE Analysis

### Spoofing

| Threat | Description | Likelihood | Impact |
|--------|-------------|------------|--------|
| Unauthorized EventBridge publisher | An attacker with AWS credentials publishes crafted events to the `transaction-event-bus`, bypassing Lambda1 entirely | Medium | High |
| IAM role impersonation | An attacker assumes Lambda execution roles to call DynamoDB or SNS directly | Low | High |

**Mitigations:**
- EventBridge rule filters events by `source: transaction.generator` and `detail-type: TransactionEvent` — events from unauthorized sources are dropped
- IAM roles use least-privilege policies scoped to specific resources and actions
- CloudTrail logs all `AssumeRole` and `PutEvents` API calls for audit

**Residual risk:** In production, EventBridge source filtering alone is insufficient — a caller with `events:PutEvents` permission on the bus can spoof the source field. A resource-based policy on the event bus restricting which IAM principals can publish would strengthen this control.

---

### Tampering

| Threat | Description | Likelihood | Impact |
|--------|-------------|------------|--------|
| Transaction data modification at rest | An attacker modifies DynamoDB records to suppress or alter anomaly records | Low | High |
| CloudTrail log tampering | An attacker deletes or modifies audit logs in S3 to cover tracks | Low | Critical |
| Terraform state file tampering | An attacker modifies the remote state file to cause infrastructure drift | Low | High |

**Mitigations:**
- DynamoDB server-side encryption with KMS CMK — data at rest is encrypted and key access is controlled
- CloudTrail log file validation enabled — digest files allow detection of any log modification or deletion
- S3 bucket versioning enabled — deleted or overwritten objects are recoverable
- S3 public access block — prevents public modification of log files
- Terraform remote state stored in S3 with versioning and SSE-S3 encryption

**Residual risk:** S3 object lock (WORM) is not configured. A highly privileged attacker could still delete versioned objects. Enabling S3 Object Lock in Governance mode would eliminate this risk.

---

### Repudiation

| Threat | Description | Likelihood | Impact |
|--------|-------------|------------|--------|
| Denial of Lambda invocation | A user denies having triggered the ingestion simulator | Low | Medium |
| Denial of DynamoDB writes | A user denies that specific transactions were written | Low | High |

**Mitigations:**
- CloudTrail management events log all Lambda `Invoke` API calls with caller identity and timestamp
- CloudTrail data events on `TransactionTable` log every `PutItem` and `GetItem` with caller identity, timestamp, and item key
- CloudTrail logs are delivered to an encrypted S3 bucket and CloudWatch Logs with 365-day retention
- CloudTrail SNS notifications alert on log delivery for real-time awareness

**Residual risk:** CloudTrail data events capture the key but not the full item payload. For complete non-repudiation of data content, DynamoDB Streams feeding into a separate immutable log store would be required.

---

### Information Disclosure

| Threat | Description | Likelihood | Impact |
|--------|-------------|------------|--------|
| Transaction data exposure at rest | Unencrypted financial data stored in DynamoDB or S3 | Low | High |
| Lambda environment variable exposure | Sensitive values (SNS ARN) exposed in Lambda configuration | Low | Medium |
| SNS email interception | Alert emails containing transaction details intercepted in transit | Low | Medium |
| CloudTrail log exposure | Audit logs containing account IDs and resource ARNs accessed publicly | Low | High |

**Mitigations:**
- All data at rest encrypted with KMS CMK — DynamoDB, S3, SQS, SNS, Lambda environment variables, CloudWatch Logs
- S3 public access block on CloudTrail bucket — no public access possible
- SNS email delivery uses TLS in transit
- KMS key policy uses least-privilege statements — only specific roles and services can use the key
- Key rotation enabled on KMS CMK

**Residual risk:** SNS email alerts contain full transaction detail including account numbers and amounts. In production, alerts should contain only a transaction reference ID with a secure link to retrieve full details from an authenticated portal.

---

### Denial of Service

| Threat | Description | Likelihood | Impact |
|--------|-------------|------------|--------|
| Lambda concurrency exhaustion | A flood of events exhausts Lambda concurrency, causing invocation failures | Medium | High |
| DynamoDB throttling | High write volume causes `PutItem` failures on the TransactionTable | Low | Medium |
| SNS publish flooding | A large volume of anomalies floods the subscriber's inbox | Medium | Low |

**Mitigations:**
- SQS Dead Letter Queue captures failed Lambda invocations for review and retry
- DynamoDB `PAY_PER_REQUEST` billing mode scales automatically to handle burst traffic without throttling
- Lambda X-Ray tracing enables visibility into performance bottlenecks

**Residual risk:** `reserved_concurrent_executions` is not set on Lambda functions due to account-level concurrency constraints. In production, setting a concurrency limit prevents one function from consuming all available concurrency and provides a blast radius boundary. SNS subscription filtering could be added to reduce alert volume for high-frequency anomaly patterns.

---

### Elevation of Privilege

| Threat | Description | Likelihood | Impact |
|--------|-------------|------------|--------|
| Overly permissive Lambda IAM role | Lambda1's role is used to access DynamoDB or SNS beyond its intended scope | Low | High |
| KMS key misuse | A service or role uses the KMS key to decrypt data it should not access | Low | High |
| Terraform state access | An attacker reads the Terraform state file to discover resource ARNs and account IDs | Low | Medium |

**Mitigations:**
- Lambda1 IAM policy is scoped to `events:PutEvents` on the specific event bus only — no DynamoDB or SNS access
- Lambda2 IAM policy is scoped to `dynamodb:PutItem` and `dynamodb:GetItem` on `TransactionTable` only, and `sns:Publish` on the specific topic
- KMS key policy uses separate least-privilege statements per service — Lambda1 role, Lambda2 role, CloudTrail, SQS, CloudWatch Logs
- Terraform state stored in S3 with SSE-S3 encryption; access controlled by S3 bucket policy

**Residual risk:** The KMS key is shared across all services. A dedicated key per service would provide stronger isolation — if one service's credentials are compromised, the blast radius is limited to that service's data only.

---

## Summary of Residual Risks

| Risk | Severity | Recommended Mitigation |
|------|----------|------------------------|
| EventBridge source spoofing | Medium | Add resource-based policy to event bus restricting publishers |
| S3 audit log permanent deletion | Medium | Enable S3 Object Lock in Governance mode on CloudTrail bucket |
| Full transaction payload in SNS alerts | Medium | Replace full detail with reference ID + authenticated retrieval link |
| No Lambda reserved concurrency | Medium | Set `reserved_concurrent_executions` in production |
| Shared KMS key across services | Low | Implement per-service KMS keys for stronger isolation |
| DynamoDB Streams for full non-repudiation | Low | Add DynamoDB Streams to immutable log store |

---

## Assumptions and Scope

- This threat model covers the AWS infrastructure layer only. Application-layer threats (input validation, injection attacks in Lambda code) are out of scope for this analysis.
- The pipeline operates in a single AWS account. Multi-account isolation (e.g. separate accounts for logging and workloads) is a recommended production hardening step not implemented here.
- Mock transaction data is used. In production, the ingestion layer would receive real payment events from an authenticated payment gateway, introducing additional trust boundary concerns at the ingestion point.
