# Goal

I want to run Claude Code authoring code in unattended mode where where and I don't have to confirm different commands that it needs to execute. This requires Claude Code to have (almost?) full permissions in the environment (settings.json deny empty?), so apparently it cannot be localhost on my private macos for security reasons. The result of the work that Claude Code is authoring will be source code which will be pushed to a GitHub repo -- I think I can set up specific permissions to avoid destructive actions.

# Roadmap

- [x] R1: Be able to complete the whole spec-driven flow end to end on the change branch. See: openspec/explore/R1-apply-flag.md (shipped via `opt-in-apply-trigger`, archived 2026-05-13)
- [x] R2: Automate onboarding and delivery of updates for adopter repos, making it as easy as possible (e.g. run one script, minimze manual actions). See: openspec/explore/R2-onboarding.md (R2.1 `install.sh init` shipped via `gh-remcc-init`, archived 2026-05-14; R2.2 `install.sh upgrade` shipped via `install-sh-upgrade`, archived 2026-05-14; R2.3 opt-in `.github/**` push ruleset for org-owned adopters — not started, see openspec/explore/R2.3-github-push-ruleset.md)
- [x] R3: The merge request that is opened by the bot after verify, to be authored by the bot and not me, so that I can do a proper code review and merge without overriding branch protection rules. (Shipped via `pr-author-github-app` — bot identity is now a dedicated GitHub App.)
- [x] R4: cloud run `opsx:verify` after apply and... automatically fix? or: highlight in PR -> human review -> another go. (Shipped via `actions-verify-after-apply`, archived 2026-05-15)
- [x] R5: clearly focus remcc on github org accounts, but keep private accounts supported; re-scan existing adopters and identify setup gaps
- [ ] R6: Codify the working loop: describe the bigger problem → iterate → plan: split into bite-sized changes → apply changes one-by-one via remcc, according to any dependency order.
