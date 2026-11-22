# Capsa: notes for Claude Code

- Read `SPEC.md` first. It covers goal, architecture, schema, API, sync, learning logic and milestones.
- Start with M0 (schema, `capsa validate`, answer checking as pure logic with tests).
- The profile in `profiles/private/` contains copyrighted textbook content:
  never commit it, and never copy it into logs, fixtures or test data. Tests use a demo profile of our own.
- Entry IDs are stable and are never renamed.
- Logic (matching, Leitner, sync state) stays pure and free of I/O, with shared test vectors for client and server.
- Open points are listed in SPEC.md section 13. Ask when a decision listed there is still open.
- Language: documentation, commit messages, code and identifiers are in English. The profile content itself stays in its original language.
