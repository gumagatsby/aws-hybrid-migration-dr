# Disaster recovery drill results

Drill run on 16 October 2026. London's app server was stopped at 2026-10-16T15:51:07Z and the application was rebuilt in eu-west-1 from replicated backups and files. Times below come from AWS (instance stop reason, RDS instance create time, EC2 launch time) and the drill log.

| Measure | Result |
|---|---|
| Recovery time (RTO): outage to app serving in eu-west-1 | **1107 seconds** (18 min 27 s) |
| Data loss window (RPO): last write London acknowledged to last write recovered | **more than 600 seconds** (none of the drill's 106 writes survived) |
| Last write London acknowledged | 2026-10-16T15:51:00Z (write #106) |
| Last drill write present after recovery | none; the restore point was earlier than the first drill write (about 15:41Z) |
| Jobs before / after | 501 / 501 (all migrated data recovered) |
| Database restore started in eu-west-1 | 2026-10-16T15:54:22Z |
| App server launched in eu-west-1 | 2026-10-16T16:08:31Z |
| App serving in eu-west-1 | 2026-10-16T16:09:34Z |

## What this shows

- **Replication lag sets the data loss.** At 16:14:46Z the latest restorable time in eu-west-1 was 16:01:13Z, about 13.5 minutes behind. Cross-region automated backup replication suits a business that can lose around 15 minutes of data.
- **The database restore is most of the recovery time.** About 14 of the 18.5 minutes went on restoring RDS before the app server could start.
- **To do better:** a cross-region read replica keeps Ireland seconds behind and can be promoted in minutes, at the cost of a second database running all the time (warm standby). Pre-baking the app into an AMI would remove the package install from the app server's boot.
