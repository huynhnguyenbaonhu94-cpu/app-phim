-- Optional one-time migration for an existing R2 settings table.
-- Preserve the same instant when moving from UTC to Vietnam local time (UTC+7).
-- The startup compatibility guard performs the same conversion when this column is absent.
ALTER TABLE `r2_settings`
  ADD COLUMN `scheduleHourVietnam` int NOT NULL DEFAULT 9;

UPDATE `r2_settings`
SET `scheduleHourVietnam` = MOD(COALESCE(`scheduleHourUtc`, 2) + 7, 24);
