# QdrantPhotoSweep QA Checklist

## Core Scan
- Launch the app on a clean database and run a full scan.
- Confirm scan progress advances steadily and the scan completes without hanging on iCloud-backed photos.
- Verify the Settings database count and stats reflect the completed run.

## Resume And Recovery
- Start a scan, background the app mid-run, then return to the foreground.
- Confirm the scan resumes instead of restarting from zero.
- Force-close during group deletion, relaunch, and verify the app recovers unfinished deletion work without crashing or losing review state.

## Review While Scanning
- Allow duplicate groups to appear while scanning is still active.
- Review one group in cards mode and one in grid mode.
- Confirm processed groups disappear from pending review and do not immediately reappear.

## Deletion Safety
- Delete a group and verify the kept item remains, the deleted items leave Photos, and the group moves out of the pending queue.
- Simulate or observe a deletion failure path and confirm the group remains recoverable instead of becoming permanently stuck.

## Reset
- Use Settings -> Clear Database.
- Confirm vector data, pending groups, sessions, and counters all reset to zero.
- Start a new scan after reset and verify previously indexed assets can be scanned again.

## Background Scan
- Let the app schedule background work after a completed session.
- Add new photos, background the app, and confirm a subsequent launch can pick up newly discovered duplicate groups.
