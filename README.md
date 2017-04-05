# certbot

Get a Let's Encrypt Certificate using Certbot.

## `runme.sh`

With exception to `clean` requires `host-name` and `email-address`

| Command   | Description                                      |
| --------- | ------------------------------------------------ |
| certbot   | get/renew LE's certficicate for `host-name`      |
| test-cert | get a test certificate                           |
| dry-run   | don't write anything                             |
| clean     | remove all certificates                          |

### `certbot`

Get a new certificate ore renews an existing one in the `letsencrypt` directory.
Example:

    runme.sh certbot virtual-host.example.com certs@example.com

`virtual-host.example.com` is the target to get Let's Encrypt certificate for.
`certs@example.com` is your email address required by LE.

### `test-cert`

Similar to `certbot` but gets a test certificate instead.

### `dry-run`

Similar to `test-cert` but don't write it to disk.

### `clean`

Removes the `letsencrypt` directory. Use it with caution after test runs only.

-------------------------------------------------------------------------------

# Usage Instruction

## Get Let's Encrypt Certificate

    docker run --rm -t -v <local-dir>:/data -p 80:80 \
        aquaron/certbot certbot <hostname> <email>

