# Log Rotation Using `/etc/logrotate.d` --- Production Guide

## Purpose

This document explains how to replace ad‑hoc log cleanup scripts (like
`logrotate-sanity.sh`) with **native OS log rotation using logrotate**.

This is the **correct production approach** because it is:

-   Predictable
-   Auditable
-   Policy-driven
-   Distribution-supported
-   Low maintenance
-   Compatible with compliance frameworks

------------------------------------------------------------------------

## When You Should Use logrotate Instead of Scripts

Use **logrotate** when you need:

  Need                              logrotate Handles
  --------------------------------- -------------------
  Prevent disks filling from logs   ✅
  Retention policies                ✅
  Compression                       ✅
  Rotation by size or time          ✅
  Service-safe log reopen           ✅
  Central policy management         ✅

------------------------------------------------------------------------

## Step 1 --- Confirm logrotate Is Installed

### RHEL / CentOS / Rocky / Alma

``` bash
rpm -qa | grep logrotate
```

### Ubuntu / Debian

``` bash
dpkg -l | grep logrotate
```

### macOS (if using brew environment)

``` bash
brew install logrotate
```

------------------------------------------------------------------------

## Step 2 --- Understand How logrotate Runs

Usually triggered by:

-   systemd timer → `logrotate.timer`
-   cron → `/etc/cron.daily/logrotate`

Check:

``` bash
systemctl status logrotate.timer
```

or:

``` bash
ls -l /etc/cron.daily/logrotate
```

------------------------------------------------------------------------

## Step 3 --- Create a Policy in `/etc/logrotate.d`

### Example Scenario

Rotate application logs in:

    /var/log/myapp/

------------------------------------------------------------------------

## Example Production Config

Create:

    /etc/logrotate.d/myapp

``` conf
/var/log/myapp/*.log {
    daily
    rotate 14
    size 50M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    dateext
    dateformat -%Y%m%d
}
```

------------------------------------------------------------------------

## Directive Explanation

  Directive       Meaning
  --------------- --------------------------------------
  daily           Rotate every day
  rotate 14       Keep 14 rotations
  size 50M        Rotate early if size exceeded
  missingok       Ignore missing files
  notifempty      Skip empty logs
  compress        gzip old logs
  delaycompress   Compress starting next rotation
  copytruncate    Safe for apps that don't reopen logs

------------------------------------------------------------------------

## Step 4 --- Test Configuration (Critical)

Never deploy without testing.

``` bash
sudo logrotate -d /etc/logrotate.conf
```

Force test run:

``` bash
sudo logrotate -f /etc/logrotate.conf
```

------------------------------------------------------------------------

## Step 5 --- Verify Status File

Usually stored at:

    /var/lib/logrotate/status

Check:

``` bash
cat /var/lib/logrotate/status
```

------------------------------------------------------------------------

## Step 6 --- Production Patterns

### High Volume Services

``` conf
size 100M
rotate 7
hourly
```

------------------------------------------------------------------------

### Compliance Environments

``` conf
rotate 90
compress
dateext
```

------------------------------------------------------------------------

### Security Logs (Never Delete Early)

``` conf
rotate 365
compress
```

------------------------------------------------------------------------

## Step 7 --- When NOT to Use copytruncate

If app supports log reopen via signal: - nginx - apache - many Java
apps - systemd services

Better:

``` conf
postrotate
    systemctl kill -s HUP myapp.service
endscript
```

------------------------------------------------------------------------

## Step 8 --- Observability / Troubleshooting

### Show recent rotations

``` bash
grep rotated /var/log/messages
```

### Manual dry run for single config

``` bash
logrotate -d /etc/logrotate.d/myapp
```

------------------------------------------------------------------------

## Mapping From Your Script to logrotate

  Your Script Function   logrotate Equivalent
  ---------------------- ------------------------
  Find large logs        size directive
  Manual cleanup         rotate count
  Manual compression     compress
  Disk triage            Policy driven rotation

------------------------------------------------------------------------

## Recommended Default Template

``` conf
/var/log/<app>/*.log {
    daily
    size 50M
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
```

------------------------------------------------------------------------

## Operational Best Practices

✔ Always test with `-d` first\
✔ Monitor disk with Prometheus / node exporter\
✔ Track rotation failures\
✔ Standardize across environments\
✔ Store configs in config management (Ansible / Terraform)

------------------------------------------------------------------------

## Enterprise Automation Pattern

Treat `/etc/logrotate.d` as **managed configuration**:

-   Ansible role
-   Chef cookbook
-   Puppet module
-   Immutable image bake step

------------------------------------------------------------------------

## Summary

If logs are filling disks, **fix the policy**, not the symptom.

logrotate is:

-   Safer
-   Standard
-   Auditable
-   Scalable
-   Already built for this problem

------------------------------------------------------------------------

## Author Note

If you are writing scripts to clean logs in production,\
you probably need logrotate instead.
