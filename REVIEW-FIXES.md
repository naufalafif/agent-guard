# AgentGuard Review Fixes Plan

## Must Fix (Bugs/Security) — DONE

- [x] 1. Delete `shell()` method — security liability in ScannerService.swift:111-139
- [x] 2. Fix DependencyManager pipe deadlock — use temp files like ScannerService
- [x] 3. Add error state to UI — users need to know when things fail
  - Added `lastError` to `ScanState`
  - Added `error` field to `MCPResult`, `SkillResult`, `ScanResult`
  - `runMCPScan` now returns descriptive errors instead of silent `.empty`
  - Error banner shown in popover when scan fails
- [x] 4. Harden config/log file permissions
  - Config file: `0o600` after save
  - Log file: `0o600` on first creation
  - Screenshot dir: `0o700` on creation
  - Replaced all deprecated `closeFile()` → `try? handle.close()`
  - Replaced deprecated `synchronizeFile()` → `try? stdout.synchronize()`

## Should Fix (Reliability)

- [ ] 5. Deduplicate config parsing and executable resolution
- [ ] 6. Fix settings not triggering rescan
- [ ] 7. Fix periodic interval not updating mid-sleep
- [ ] 8. Remove NotificationCenter observer leak
- [ ] 9. Replace deprecated `closeFile()`/`synchronizeFile()`

## Nice to Have (MVP Polish)

- [ ] 10. Add macOS notifications for new threats
- [ ] 11. Add scanner update mechanism
- [ ] 12. Add scan cancellation on quit
- [ ] 13. Handle empty MCP section state
