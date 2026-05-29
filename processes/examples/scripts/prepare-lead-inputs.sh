#!/usr/bin/env bash
# Demo script for the subprocess-demo.sop.yaml example.
# Emits a fixed lead payload so the automated step has deterministic output.
printf '{"lead_name": "Demo User", "lead_email": "demo@example.com", "source": "website"}\n'
