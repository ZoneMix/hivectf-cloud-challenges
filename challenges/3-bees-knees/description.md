# Challenge 3: Bee's Knees

**Category:** Cloud / Web  
**Points:** 300  
**Difficulty:** Medium  
**Flag Format:** `HiveCTF{}`

## Scenario

HiveWatch Industries monitors thousands of bee hives across the Great Plains using a network of IoT sensors. Each sensor reports real-time temperature, humidity, and colony population data back to a central cloud platform.

To support partner integrations with agricultural research labs, HiveWatch exposes a public API for querying sensor data. The API was built quickly by an intern and rushed to production -- management said the data is "non-sensitive" so security review was skipped.

Your task: the HiveWatch API is hiding something it shouldn't be. Find it.

## Connection Info

**API Base URL:**

```
{API_BASE_URL}
```

Known sensor IDs: `HV-001`, `HV-002`, `HV-003`

## Hints

1. You know the base URL, but not what endpoints exist. Maybe you should go looking for them.
2. The sensor API seems to accept various types of input for its query parameter. What happens when you give it something unexpected?
3. Error messages from the API can be very revealing about the backend technology and how your input is processed. https://github.com/mahaloz/ctf-wiki-en/blob/master/docs/pwn/linux/sandbox/python-sandbox-escape.md
4. Lambda functions run with credentials that can be found in the execution environment.
5. Temporary AWS credentials open doors to other services in the account.
