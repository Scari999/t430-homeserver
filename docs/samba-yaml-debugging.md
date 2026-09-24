# Postmortem: Samba Container Crash Loop — Compose Command Field Truncation

## Symptom

The Samba container in the stack repeatedly crash-looped on startup. No
obvious cause was visible from `docker ps` beyond a restarting state.

## Investigation

- `docker logs samba` showed Samba's user-creation step failing, with the
  password value missing from the command it received.
- `docker inspect samba --format '{{json .Config.Cmd}}'` revealed the exact
  argument list passed into the container — confirming the command string
  had been altered before it ever reached the container.

## Root cause

The `dperson/samba` image expects its `-u` flag in `username;password`
format. The Compose file originally defined `command:` as a single string
value. Docker Compose tokenizes string-form `command:` values using
shell-like parsing rules, where `;` is treated as a control character
rather than literal text. Everything after the semicolon was silently
dropped — the password never reached the container, with no warning or
error at the Compose level.

## Fix

Switched `command:` from string form to YAML list form, with each argument
as its own list item:

```yaml
command:
  - -u
  - boss;eggbacon
```

In list form, each item is passed through literally with no shell-style
interpretation, so the semicolon is preserved as intended.

## Secondary issue: permission denial

After fixing the truncation, files written to the share via a client
(Nautilus) were rejected with a permissions error. Root cause: a UID
mismatch between the Samba container's internal user and the host
directory's ownership. Fixed by adding the `-p` flag, which auto-configures
share permissions to match the specified user.

## Lesson

Docker Compose's string-form `command:` isn't safe for values containing
shell metacharacters (`;`, `|`, `&`) — it truncates silently instead of
raising an error, which makes this class of bug easy to miss. List form
removes the ambiguity and should be the default for any command value
containing punctuation.
