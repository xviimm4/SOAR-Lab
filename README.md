# SOAR-Lab

A hands-on lab for **Security Orchestration, Automation and Response (SOAR)** integrating open-source security tools: **Wazuh**, **TheHive**, **Cortex**, and **Shuffle**.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Components](#components)
- [System Requirements](#system-requirements)
- [Directory Structure](#directory-structure)
- [Deployment Guide](#deployment-guide)
- [Workflow](#workflow)
- [Configuration Details](#configuration-details)
- [Active Response](#active-response)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              SOAR-Lab Pipeline                                   │
│                                                                                  │
│  Wazuh Agent        Wazuh Manager         Shuffle (SOAR Orchestrator)            │
│  (Endpoint)  ─────▶  (SIEM/EDR)  ──────▶  Webhook ──▶ Alert/Case ──▶ Cortex    │
│                                                                         │        │
│                          ┌──────────────────────────────────────────────┘        │
│                          ▼                                                       │
│                    VirusTotal / Analyzer                                         │
│                          │                                                       │
│                    ┌─────▼──────┐    Malicious?                                 │
│                    │  Discord   │ ──(YES)──▶ GET Token ──▶ Delete File           │
│                    │ Notification│          (Wazuh API)    (Active Response)     │
│                    └────────────┘                                                │
└──────────────────────────────────────────────────────────────────────────────────┘
```

When a security event occurs on an endpoint (e.g., a suspicious file is dropped into a monitored directory):
1. **Wazuh Agent** detects the change via **Syscheck** (File Integrity Monitoring).
2. **Wazuh Manager** receives the alert and forwards it to **Shuffle** via a configured webhook.
3. **Shuffle** creates an Alert → Case in **TheHive**, attaching the agent IP and file hash as observables.
4. **Cortex** analyzes the file hash through **VirusTotal** (or an equivalent analyzer).
5. **Shuffle** sends the analysis result as a notification to **Discord**.
6. If the file is determined to be malicious, Shuffle retrieves the **Wazuh API Token** and triggers **Active Response** to delete the file on the endpoint.

---

## Components

| Component | Version | Port | Role |
|---|---|---|---|
| **Wazuh Manager** | Latest | — | SIEM & EDR – Collects and analyzes logs, monitors file integrity |
| **Wazuh Agent** | Latest | — | Installed on endpoints to monitor system events |
| **TheHive** | 4.x | 9000 | Security incident response platform (Case & Alert Management) |
| **Cortex** | Latest | 9001 | Executes analyzers and responders |
| **Shuffle** | Latest | 3001/5001 | SOAR – Orchestrates and automates security workflows |
| **Elasticsearch** | 7.17.9 | 9200 | Search engine backend for TheHive and Cortex |
| **Cassandra** | 3.11 | 9042 | Primary database for TheHive |
| **OpenSearch** | 2.5.0 | 9200 | Database backend for Shuffle |

---

## System Requirements

- **Docker** and **Docker Compose** (latest version)
- RAM: Minimum **8 GB** (16 GB recommended)
- Disk: Minimum **20 GB** free space
- OS: Linux (Ubuntu 20.04+) or any Docker-compatible environment

---

## Directory Structure

```
SOAR-Lab/
├── thehive-cortex-shuffle_docker/
│   └── docker-compose.yml      # Docker Compose for TheHive, Cortex, Shuffle
│
├── wazuh/
│   ├── wazuh-manager/
│   │   ├── ossec_integration.conf      # Shuffle webhook integration config
│   │   ├── active_response_cfg.xml     # Active Response configuration
│   │   └── syscheck_config.xml         # File Integrity Monitoring config
│   │
│   └── script/
│       └── active-respone/
│           └── custom-delete.sh        # Auto file deletion script
│
└── workflow/
    └── SOAR.json                       # Shuffle workflow (import into Shuffle)
```
---

## Deployment Guide

### Step 1: Start TheHive, Cortex, and Shuffle

```bash
cd thehive-cortex-shuffle_docker
docker-compose up -d
```

Check container status:

```bash
docker-compose ps
```

| Service | URL |
|---|---|
| TheHive | http://localhost:9000 |
| Cortex | http://localhost:9001 |
| Shuffle Frontend | http://localhost:3001 |
| Shuffle Backend | http://localhost:5001 |

### Step 2: Configure Wazuh Manager

#### 2.1. Shuffle Webhook Integration

Add the following block to `/var/ossec/etc/ossec.conf` on the Wazuh Manager:

```xml
<ossec_config>
  <integration>
    <name>custom-shuffle</name>
    <hook_url>YOUR_SHUFFLE_WEBHOOK_URL</hook_url>
    <level>7</level>
    <alert_format>json</alert_format>
  </integration>
</ossec_config>
```

> Replace `YOUR_SHUFFLE_WEBHOOK_URL` with the webhook URL from your imported Shuffle workflow.

#### 2.2. File Integrity Monitoring (Syscheck)

Add the following to the Wazuh Manager configuration to monitor a specific directory:

```xml
<syscheck>
  <directories realtime="yes" check_all="yes">/home/username/Downloads</directories>
</syscheck>
```

#### 2.3. Active Response Configuration

Add the following to enable automatic file deletion:

```xml
<command>
  <name>custom_delete</name>
  <executable>custom-delete.sh</executable>
  <timeout_allowed>no</timeout_allowed>
</command>

<active-response>
  <command>custom_delete</command>
  <location>local</location>
</active-response>
```

### Step 3: Install the Active Response Script

```bash
# Copy the script to the Wazuh Agent
cp wazuh/script/active-respone/custom-delete.sh /var/ossec/active-response/bin/custom-delete.sh

# Grant execute permission
chmod +x /var/ossec/active-response/bin/custom-delete.sh
```

### Step 4: Import Workflow into Shuffle

1. Open Shuffle at `http://localhost:3001`
2. Log in with default credentials (`admin` / `password`)
3. Go to **Workflows** → **Import** → Select `workflow/SOAR.json`
4. Configure TheHive authentication in the workflow:
   - Add the TheHive API Key
   - Update the TheHive instance URL (`http://localhost:9000`)
5. Copy the **Webhook URL** from the trigger node and update it in the Wazuh integration config

### Step 5: Configure TheHive ↔ Cortex Connection

1. Generate an API Key from Cortex: **Settings → API Keys**
2. Update it in `docker-compose.yml`:
   ```yaml
   --cortex-keys
   <YOUR_CORTEX_KEY>
   ```

---

## Workflow

The Shuffle workflow (`SOAR.json`) consists of **12 nodes** split into 2 main phases:

### Phase 1 – Collection & Case Creation

```
[Webhook Wazuh]
       │
       ▼
[Get time]                  ← Get current Unix timestamp (Python)
       │
       ▼
[Create Alert]              ← Create an Alert in TheHive
       │
       ▼
[Create Case]               ← Promote Alert to a Case
       │
       ▼
[Create observable IP]      ← Attach agent IP to the Case
       │
    (1 condition)
       │
       ▼
[Create observable hash]    ← Attach file SHA256 hash to the Case
       │
       ▼
[Run Cortex Analysis]       ← Submit the hash to Cortex for analysis
```

### Phase 2 – Analysis & Automated Response

```
[Run Cortex Analysis]
       │
       ▼
[Get result]                ← Poll Cortex API for analysis result (Python)
       │
       ▼
[Sent Discord]              ← Send analysis result notification to Discord
       │
    (2 conditions)          ← Branch: malicious / safe
       │
       ▼ (if malicious)
[GET Token]                 ← Retrieve JWT Token from Wazuh API
       │
       ▼
[Delete Malicious File]     ← Trigger Wazuh Active Response to delete the file
```

### Node Details

| # | Node | Type | Description |
|---|---|---|---|
| 1 | `Webhook Wazuh` | Trigger | Receives alert JSON from Wazuh Manager |
| 2 | `Get time` | Python | Gets current Unix timestamp (ms) for the Alert |
| 3 | `Create Alert` | TheHive API | Creates an Alert with Wazuh data (rule, agent IP, timestamp) |
| 4 | `Create Case` | TheHive API | Promotes Alert to a Case for SOC investigation |
| 5 | `Create observable IP` | TheHive API | Attaches agent IP address to the Case |
| 6 | `Create observable hash` | TheHive API | Attaches SHA256 file hash to the Case *(only when hash exists)* |
| 7 | `Run Cortex Analysis` | HTTP/Cortex | Submits file hash to Cortex (VirusTotal analyzer) |
| 8 | `Get result` | Python | Polls Cortex API for analysis result |
| 9 | `Sent Discord` | HTTP/Webhook | Sends analysis report to a Discord channel |
| 10 | *(2 conditions)* | Condition | Branch: `malicious` → proceed to delete, `safe` → stop |
| 11 | `GET Token` | HTTP/Wazuh API | Authenticates and retrieves JWT token from Wazuh Manager |
| 12 | `Delete Malicious File` | HTTP/Wazuh API | Calls Wazuh Active Response API to delete the file on the endpoint |

---

## Configuration Details

### Alert Structure Sent to TheHive

```json
{
  "type": "Wazuh",
  "source": "WazuhManager",
  "sourceRef": "incident-<timestamp>",
  "title": "IP Agent: <agent_ip> <alert_title>",
  "description": "<rule_description>",
  "severity": 2,
  "tlp": 2,
  "tags": ["wazuh", "auto"],
  "date": <unix_timestamp_ms>
}
```

### Automatically Created Observables

| Observable | Type | Data Source |
|---|---|---|
| Agent IP | `ip` | `exec.all_fields.agent.ip` |
| File Hash | `hash` | `exec.all_fields.syscheck.sha256_after` |

---

## Active Response

The `custom-delete.sh` script is triggered by Wazuh to automatically remove malicious files from endpoints.

### Safety Features

- **Path Validation**: Validates the file path before deletion
- **System Protection**: Blocks deletion of system files under `/etc`, `/bin`, `/sbin`, `/usr`
- **Logging**: Logs all activity to `/var/ossec/logs/active-responses.log`

### Execution Logic

```bash
# 1. Read JSON input from Wazuh via stdin
# 2. Extract the file path from the syscheck alert
# 3. Validate path is non-empty and not a system directory
# 4. Delete the file if it exists
# 5. Log the result
```

### Example Log Output

```
2025/05/13 01:30:00 custom-delete.sh: Successfully deleted: /home/user/Downloads/malware.exe
2025/05/13 01:30:01 custom-delete.sh: Denied - Deletion of system file blocked: /etc/passwd
```

---

## Use Case: File Integrity Monitoring + Auto-Response

1. An attacker drops a suspicious file into `/home/user/Downloads/`
2. **Wazuh Syscheck** detects the new file and generates an alert (level ≥ 7)
3. **Wazuh Integration** forwards the alert JSON to the Shuffle webhook
4. **Shuffle** automatically:
   - Creates an **Alert** in TheHive
   - Promotes it to a **Case** for investigation
   - Attaches the **agent IP** and **file hash** as observables
5. **Cortex** analyzes the hash via VirusTotal
6. **Shuffle** sends the result to **Discord**
7. If malicious, **Wazuh Active Response** triggers `custom-delete.sh` to remove the file
8. The SOC analyst reviews the full Case in TheHive for deeper investigation

---

## Security Notice

> **Important:** This is a lab environment. Before moving to production, make sure to:
> - Change all default passwords
> - Enable SSL/TLS on all services
> - Restrict network access between containers
> - Replace default API keys in `docker-compose.yml`

---

## References

- [Wazuh Documentation](https://documentation.wazuh.com/)
- [TheHive Documentation](https://docs.strangebee.com/)
- [Cortex Documentation](https://docs.strangebee.com/cortex/)
- [Shuffle Documentation](https://shuffler.io/docs)

---

## Author

**Hoang Quan** — SOAR Lab for Security Research & Learning
