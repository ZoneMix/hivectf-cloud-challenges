# Challenge 2: Role Call

**Category:** Cloud  
**Points:** 200  
**Difficulty:** Easy-Medium  

## Story

Welcome to your first day as an intern at HiveCorp! HR has provisioned you a set of minimal AWS credentials so you can "get familiar with the environment." They assured you that your access is extremely limited -- just enough to look around, nothing more.

But you're curious. Surely there's something interesting hiding in this cloud environment. Maybe your lowly intern account can reach more than they think...

## Objective

Find the flag hidden somewhere in HiveCorp's AWS infrastructure.

## Connection Info

| Field | Value |
|-------|-------|
| **AWS Access Key ID** | `<provided at competition>` |
| **AWS Secret Access Key** | `<provided at competition>` |
| **Region** | `us-east-1` |

Configure your AWS CLI:

```
aws configure --profile hivectf-ch2
```

Enter the Access Key ID and Secret Access Key when prompted. Set the region to `us-east-1`.

## Flag Format

`HiveCTF{...}`

## Hints

1. Sometimes the best way up is to look at what roles are available to you.
2. Who are you? What can you become?
3. Not every function tells the truth about what it holds inside.
