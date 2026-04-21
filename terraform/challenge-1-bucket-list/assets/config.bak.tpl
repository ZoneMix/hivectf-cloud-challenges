# CloudNine Technologies - Employee Portal Configuration
# Last updated: 2026-03-15
# Author: j.mitchell@cloudnine.io
# WARNING: This file contains sensitive credentials. Do not commit to version control.

[database]
host = portal-db.internal.cloudnine.io
port = 5432
name = employee_portal
user = portal_svc
password = Cldn9!Pr0d#2026

[aws]
# Service account for portal backend - used by the employee directory lookup
aws_access_key_id = ${access_key}
aws_secret_access_key = ${secret_key}
region = us-east-1

[application]
debug = false
log_level = INFO
session_timeout = 3600
base_url = https://portal.internal.cloudnine.io

[redis]
host = cache.internal.cloudnine.io
port = 6379
db = 2

[smtp]
host = smtp.cloudnine.io
port = 587
from = noreply@cloudnine.io
