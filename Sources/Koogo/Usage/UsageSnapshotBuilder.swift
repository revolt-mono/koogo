import Foundation

struct UsagePeriodIntervals: Equatable {
    struct Comparison: Equatable {
        let current: Range<Date>
        let previous: Range<Date>

        fileprivate init(
            component: Calendar.Component,
            containing date: Date,
            calendar: Calendar
        ) {
            guard
                let current = calendar.dateInterval(of: component, for: date),
                let previousDate = calendar.date(byAdding: component, value: -1, to: current.start),
                let previous = calendar.dateInterval(of: component, for: previousDate)
            else {
                preconditionFailure("calendar must provide current and previous period intervals")
            }

            self.current = current.start..<current.end
            self.previous = previous.start..<previous.end
        }
    }

    let day: Comparison
    let week: Range<Date>
    let month: Comparison

    init(containing date: Date, calendar: Calendar) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            preconditionFailure("calendar must provide a week interval")
        }

        day = Comparison(component: .day, containing: date, calendar: calendar)
        self.week = week.start..<week.end
        month = Comparison(component: .month, containing: date, calendar: calendar)
    }
}

enum UsageSnapshotBuilder {
    private struct ModelUsage {
        var occurrences = 0
        var reasoningEfforts: [String: Int] = [:]

        mutating func add(reasoningEffort: String?) {
            occurrences += 1
            if let reasoningEffort {
                reasoningEfforts[reasoningEffort, default: 0] += 1
            }
        }

        mutating func merge(_ other: ModelUsage) {
            occurrences += other.occurrences
            reasoningEfforts.merge(other.reasoningEfforts, uniquingKeysWith: +)
        }
    }

    private struct Accumulator {
        var processedTokens: Decimal = 0
        var costUSD: Decimal = 0
        var models: [UsageModelReference: ModelUsage] = [:]

        mutating func add(_ usage: UsageRecord) {
            processedTokens += Decimal(usage.processedTokens)
            costUSD += usage.costUSD
            if let turn = usage.modelTurn {
                models[turn.model, default: ModelUsage()].add(
                    reasoningEffort: turn.reasoningEffort
                )
            }
        }

        mutating func merge(_ other: Accumulator) {
            processedTokens += other.processedTokens
            costUSD += other.costUSD
            for (model, usage) in other.models {
                models[model, default: ModelUsage()].merge(usage)
            }
        }

        func favorite(piModels: PiModelCatalog) -> ProviderUsageSnapshot.Favorite? {
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

    static func build(
        events: some Sequence<UsageEvent>,
        intervals: UsagePeriodIntervals,
        calendar: Calendar,
        piModels: PiModelCatalog = .empty
    ) -> UsageSnapshot {
        var daysByProvider: [UsageProvider: [Date: Accumulator]] = [:]

        for event in events {
            let usage = event.usage
            daysByProvider[event.provider, default: [:]][
                calendar.startOfDay(for: usage.timestamp),
                default: Accumulator()
            ].add(usage)
        }

        return UsageSnapshot(
            codex: providerSnapshot(
                from: daysByProvider[.codex] ?? [:],
                intervals: intervals,
                piModels: piModels
            ),
            claude: providerSnapshot(
                from: daysByProvider[.claude] ?? [:],
                intervals: intervals,
                piModels: piModels
            ),
            piAgent: providerSnapshot(
                from: daysByProvider[.piAgent] ?? [:],
                intervals: intervals,
                piModels: piModels
            ),
            previousDay: daysByProvider.values.reduce(UsagePeriodSnapshot.zero) {
                $0 + periodSnapshot(from: $1, in: intervals.day.previous)
            },
            previousMonth: daysByProvider.values.reduce(UsagePeriodSnapshot.zero) {
                $0 + periodSnapshot(from: $1, in: intervals.month.previous)
            }
        )
    }

    private static func providerSnapshot(
        from days: [Date: Accumulator],
        intervals: UsagePeriodIntervals,
        piModels: PiModelCatalog
    ) -> ProviderUsageSnapshot {
        var total = Accumulator()
        for day in days.values {
            total.merge(day)
        }
        return ProviderUsageSnapshot(
            favorite: total.favorite(piModels: piModels),
            today: periodSnapshot(from: days, in: intervals.day.current),
            week: periodSnapshot(from: days, in: intervals.week),
            month: periodSnapshot(from: days, in: intervals.month.current),
            dailyMonth: UsageMonthSnapshot(
                range: intervals.month.current,
                days:
                    days
                    .filter { intervals.month.current.contains($0.key) }
                    .sorted { $0.key < $1.key }
                    .map { date, accumulator in
                        UsageDaySnapshot(
                            date: date,
                            processedTokens: accumulator.processedTokens,
                            costUSD: accumulator.costUSD
                        )
                    }
            )
        )
    }

    private static func periodSnapshot(
        from days: [Date: Accumulator],
        in interval: Range<Date>
    ) -> UsagePeriodSnapshot {
        var processedTokens: Decimal = 0
        var costUSD: Decimal = 0
        for (date, day) in days where interval.contains(date) {
            processedTokens += day.processedTokens
            costUSD += day.costUSD
        }
        return UsagePeriodSnapshot(
            processedTokens: processedTokens,
            costUSD: costUSD
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
