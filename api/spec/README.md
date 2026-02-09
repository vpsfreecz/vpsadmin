# vpsAdmin API specs

This directory contains the new, API-only RSpec suite.

The previous spec suite was removed because it relied on obsolete schema columns and outdated HaveAPI spec helpers and was no longer maintainable.

Next steps (Session 02+):
- boot the real API Rack app under Rack::Test
- create/prepare a test database from db/schema.rb
- add deterministic seed data and auth helpers
- write request specs for each HaveAPI resource action
