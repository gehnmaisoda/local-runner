import Foundation

/// スケジュール判定のピュアロジック。副作用から分離してテスト容易性を確保する。
public enum ScheduleLogic {
    /// 現在時刻に基づいて実行すべきタスクを返す。
    public static func dueTasks(
        from tasks: [TaskDefinition],
        nextFireDates: [String: Date],
        at now: Date
    ) -> [TaskDefinition] {
        tasks.filter { task in
            guard task.enabled,
                  let nextFire = nextFireDates[task.id],
                  nextFire <= now else { return false }
            return true
        }
    }

    /// 全有効タスクの次回実行日時を計算する。
    public static func calculateNextFireDates(
        for tasks: [TaskDefinition],
        after now: Date
    ) -> [String: Date] {
        var dates: [String: Date] = [:]
        for task in tasks where task.enabled {
            dates[task.id] = task.schedule.nextFireDate(after: now)
        }
        return dates
    }
}
