# Service Watchdog

## Overview

`service-watchdog.sh` is a Bash-based service monitor intended for:

• Legacy environments\
• Restricted systemd access\
• Interview demonstration\
• Non-production automation

------------------------------------------------------------------------

## 🚨 Production Pattern (Recommended)

In real RHEL / enterprise Linux environments, **do NOT run custom
watchdog loops**.

Use systemd native capabilities instead.

Why:

• Native restart handling\
• Built-in rate limiting (flap protection)\
• Integrated logging (journalctl)\
• Clean alert hooks (OnFailure)\
• Lower operational complexity

------------------------------------------------------------------------

## Step 1 --- Configure Restart Behavior

Edit your service:

    sudo systemctl edit myservice.service

Add:

    [Service]
    Restart=on-failure
    RestartSec=5

    [Unit]
    StartLimitIntervalSec=60
    StartLimitBurst=2
    OnFailure=alert-email@%n.service

Meaning:

  Setting                    Meaning
  -------------------------- -----------------------------------------
  Restart=on-failure         Restart if service crashes
  RestartSec=5               Wait 5 seconds between restart attempts
  StartLimitBurst=2          Max 2 failures
  StartLimitIntervalSec=60   Within 60 seconds window
  OnFailure                  Trigger alert workflow

------------------------------------------------------------------------

## Step 2 --- Create Alert Unit

    /etc/systemd/system/alert-email@.service

    [Unit]
    Description=Email alert for failed unit %i

    [Service]
    Type=oneshot
    ExecStart=/usr/local/sbin/send-service-failure-email.sh %i

------------------------------------------------------------------------

## Step 3 --- Alert Script

    /usr/local/sbin/send-service-failure-email.sh

``` bash
#!/usr/bin/env bash
set -euo pipefail

UNIT="${1:?missing unit}"
HOST="$(hostname -f 2>/dev/null || hostname)"

LOGS="$(journalctl -u "$UNIT" -n 100 --no-pager || true)"

{
  echo "ALERT: systemd unit failed"
  echo "Host: $HOST"
  echo "Unit: $UNIT"
  echo
  echo "$LOGS"
} | mail -s "ALERT: $UNIT failed on $HOST" ops@example.com
```

------------------------------------------------------------------------

## Why This Is Better Than Bash Watchdogs

  Feature            Bash Loop      systemd Native
  ------------------ -------------- ----------------
  Restart logic      Manual         Built-in
  Flap protection    Custom logic   Built-in
  Alert hooks        Custom         Native
  Logging            Manual         journalctl
  Operational risk   Higher         Lower

------------------------------------------------------------------------

## Testing

    sudo systemctl daemon-reload
    sudo systemctl restart myservice
    sudo systemctl stop myservice

Check:

    journalctl -u alert-email@myservice.service

------------------------------------------------------------------------

## Real Enterprise Note

Many orgs replace email with:

• PagerDuty\
• OpsGenie\
• Datadog monitors\
• Splunk alerts\
• Prometheus Alertmanager

Systemd simply becomes the failure signal generator.
