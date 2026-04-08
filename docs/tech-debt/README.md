# Tech debt

Record debt that should not disappear into chat history.

Recommended fields:
- debt item
- impact
- why it was deferred
- trigger for paying it down
- related plan or report

## Entries

| Debt item | Impact | Why deferred | Trigger to pay down | Related plan/report |
| --- | --- | --- | --- | --- |
| CLAUDE.md line 14 の "proceed through /self-review, /verify, /test" がsubagent委譲を明示していない。line 21 の新ポリシーと表面上矛盾する。 | 新規読者が line 14 と line 21 を別フローと解釈するリスク | 今回のスコープはline 21のみ変更。line 14の修正は計画の非ゴール | CLAUDE.md 次回編集時、または混乱報告が発生したとき | docs/reports/self-review-2026-04-08-subagent-trigger-policy.md |
