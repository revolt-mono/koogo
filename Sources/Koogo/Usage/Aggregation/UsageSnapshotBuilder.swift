import Foundation

enum UsageSnapshotBuilder {
    private struct Totals {
        var processedTokens: Decimal = 0
        var costUSD: Decimal = 0

        mutating func add(_ usage: UsageRecord) {
            processedTokens += Decimal(usage.processedTokens)
            costUSD += usage.costUSD
        }

        var snapshot: UsagePeriodSnapshot {
            UsagePeriodSnapshot(
                processedTokens: processedTokens,
                costUSD: costUSD
            )
        }
    }

    private struct ModelUsage {
        var occurrences = 0
        var reasoningEfforts: [String: Int] = [:]

        mutating func add(reasoningEffort: String?) {
            occurrences += 1
            if let reasoningEffort {
                reasoningEfforts[reasoningEffort, default: 0] += 1
            }
        }
    }

    private struct FavoriteAccumulator {
        var models: [UsageModelReference: ModelUsage] = [:]

        mutating func add(_ turn: UsageRecord.ModelTurn?) {
            if let turn {
                models[turn.model, default: ModelUsage()].add(
                    reasoningEffort: turn.reasoningEffort
                )
            }
        }

        func snapshot(piModels: PiModelCatalog) -> ProviderUsageSnapshot.Favorite? {
            guard
                let (model, usage) = models.max(by: { lhs, rhs in
                    lhs.value.occurrences == rhs.value.occurrences
                        ? lhs.key.sortKey > rhs.key.sortKey
                        : lhs.value.occurrences < rhs.value.occurrences
                })
            else {
                return nil
            }
            return ProviderUsageSnapshot.Favorite(
                modelName: model.displayName(piModels: piModels),
                reasoningEffort: usage.reasoningEfforts.max { lhs, rhs in
                    lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
                }?.key
            )
        }
    }

    private struct ProviderAccumulator {
        var favorite = FavoriteAccumulator()
        var today = Totals()
        var week = Totals()
        var month = Totals()
        var monthByDay: [Date: Totals] = [:]

        mutating func add(
            _ usage: UsageRecord,
            intervals: UsagePeriodIntervals,
            calendar: Calendar
        ) {
            favorite.add(usage.modelTurn)
            if intervals.day.current.contains(usage.timestamp) {
                today.add(usage)
            }
            if intervals.week.contains(usage.timestamp) {
                week.add(usage)
            }
            if intervals.month.current.contains(usage.timestamp) {
                month.add(usage)
                monthByDay[
                    calendar.startOfDay(for: usage.timestamp),
                    default: Totals()
                ].add(usage)
            }
        }

        func snapshot(
            intervals: UsagePeriodIntervals,
            piModels: PiModelCatalog
        ) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                favorite: favorite.snapshot(piModels: piModels),
                today: today.snapshot,
                week: week.snapshot,
                month: month.snapshot,
                dailyMonth: UsageMonthSnapshot(
                    range: intervals.month.current,
                    days: monthByDay.sorted { $0.key < $1.key }.map {
                        UsageDaySnapshot(
                            date: $0.key,
                            processedTokens: $0.value.processedTokens,
                            costUSD: $0.value.costUSD
                        )
                    }
                )
            )
        }
    }

    static func build(
        events: some Sequence<UsageEvent>,
        intervals: UsagePeriodIntervals,
        calendar: Calendar,
        piModels: PiModelCatalog = .empty
    ) -> UsageSnapshot {
        var codex = ProviderAccumulator()
        var claude = ProviderAccumulator()
        var piAgent = ProviderAccumulator()
        var previousDay = Totals()
        var previousMonth = Totals()

        for event in events {
            let usage = event.usage
            switch event.provider {
            case .codex:
                codex.add(usage, intervals: intervals, calendar: calendar)
            case .claude:
                claude.add(usage, intervals: intervals, calendar: calendar)
            case .piAgent:
                piAgent.add(usage, intervals: intervals, calendar: calendar)
            }
            if intervals.day.previous.contains(usage.timestamp) {
                previousDay.add(usage)
            }
            if intervals.month.previous.contains(usage.timestamp) {
                previousMonth.add(usage)
            }
        }

        return UsageSnapshot(
            codex: codex.snapshot(intervals: intervals, piModels: piModels),
            claude: claude.snapshot(intervals: intervals, piModels: piModels),
            piAgent: piAgent.snapshot(intervals: intervals, piModels: piModels),
            previousDay: previousDay.snapshot,
            previousMonth: previousMonth.snapshot
        )
    }
}

private extension UsageModelReference {
    var sortKey: String {
        switch self {
        case .codex(let id, _): "codex/\(id)"
        case .claude(let id, _): "claude/\(id)"
        case .piAgent(let provider, let id): "pi/\(provider)/\(id)"
        }
    }

    func displayName(piModels: PiModelCatalog) -> String {
        switch self {
        case .codex(_, let name), .claude(_, let name): name
        case .piAgent(let provider, let id):
            piModels.displayName(provider: provider, model: id)
        }
    }
}
