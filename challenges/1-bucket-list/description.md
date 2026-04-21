# Bucket List

**Category:** Cloud
**Points:** 100
**Difficulty:** Easy

---

## Description

**CloudNine Technologies** just launched their brand-new marketing website. Their cloud team was in such a rush to go live that the security review got pushed to "next sprint" -- you know how that goes.

Take a look at their site and see if the dev team left anything interesting behind. Rumor has it they're not great at cleaning up after themselves.

**Website:** `http://<BUCKET_NAME>.s3-website-us-east-1.amazonaws.com`

> *Replace `<BUCKET_NAME>` with the actual bucket name provided on the CTF scoreboard.*

## Hints

1. What does a web browser show you versus what actually lives in the source code?
2. S3 buckets can hold more files than what a website links to.
3. Configuration files sometimes contain more than just settings.

## Flag Format

```
HiveCTF{...}
```
