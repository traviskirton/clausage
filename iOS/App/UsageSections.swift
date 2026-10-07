import SwiftUI

// MARK: Shared card chrome

/// iOS cards: Paper on the Paper → Paper 2 gradient, radius 22, a hairline edge.
struct BrandCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("Paper").opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color("Hairline"), lineWidth: 1))
    }
}

extension View {
    func brandCard(padding: CGFloat = 16) -> some View { modifier(BrandCard(padding: padding)) }
}

/// Section title, outside its card: Bricolage 22, tracked −3%, 12pt above the card.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.clausageDisplay(22)).brandTracking(-0.03, size: 22).foregroundStyle(Color("Ink"))
            .accessibilityAddTraits(.isHeader)
    }
}

/// A titled section: the header, then its card 12pt below.
struct BrandSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            content
        }
    }
}

// MARK: Title row

/// The large title: the tally at 44pt, "Clausage" in Bricolage 38, and the plan chip on the trailing edge
/// (with the org name under it on Team and Enterprise).
struct TitleRow: View {
    let plan: Plan?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Tally(size: 44, filled: 4, slash: 1)
            Text("Clausage").font(.clausageDisplay(38)).brandTracking(-0.035, size: 38).foregroundStyle(Color("Ink"))
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let plan {
                VStack(alignment: .trailing, spacing: 3) {
                    PlanChip(text: plan.badge)
                    if let org = plan.orgName {
                        Text(org).font(.system(size: 11)).foregroundStyle(Color("Ink2")).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Plan: \(plan.badge)" + (plan.orgName.map { ", \($0)" } ?? ""))
            }
        }
    }
}

/// Ink capsule, Paper text in Bricolage 15.
struct PlanChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.clausageDisplay(15)).brandTracking(-0.01, size: 15)
            .foregroundStyle(Color("Paper"))
            .padding(.top, 7).padding(.bottom, 8).padding(.horizontal, 12)
            .background(Color("Ink"), in: Capsule())
            .lineLimit(1).fixedSize()
    }
}

// MARK: Empty state (no plan limits, e.g. Enterprise)

struct NothingToCount: View {
    var body: some View {
        VStack(spacing: 10) {
            Tally(size: 44, filled: 4, ink: Color("Ink3").opacity(0.45), empty: Color("Ink3").opacity(0.2))
            Text("Nothing to count").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color("Ink"))
            Text("Your org didn’t set any plan limits, so there’s nothing to tally. Go wild, responsibly. Usage credits still show below.")
                .font(.system(size: 14)).foregroundStyle(Color("Ink2"))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Weekly running total (5b, states 6a–6f)

struct RunningTotalCard: View {
    let chart: WeeklyChart?
    let level: Forecast.Level
    let now: Date

    var body: some View {
        BrandSection(title: "All models this week") {
            Group {
                if let chart {
                    VStack(alignment: .leading, spacing: 14) {
                        RunningTotalChart(chart: chart, level: level, now: now)
                            .frame(height: 148)
                        VStack(alignment: .leading, spacing: 4) {
                            if let headline = chart.headline {
                                Text(headline).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color("Ink"))
                            }
                            Text(chart.caption).font(.system(size: 13)).foregroundStyle(Color("Ink2"))
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    NotEnoughYet()
                }
            }
            .brandCard()
        }
    }
}

// MARK: This week by product (3d)

struct ProductCard: View {
    let breakdown: ProductBreakdown

    var body: some View {
        if let top = breakdown.rows.first {
            BrandSection(title: "This week by product") {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(top.percent.rounded()))%")
                            .font(.clausagePercent(48)).brandTracking(-0.05, size: 48).foregroundStyle(Color("Ink"))
                        Text("came from \(top.name)").font(.system(size: 15, weight: .medium)).foregroundStyle(Color("Ink"))
                    }
                    if breakdown.rows.count > 1 {
                        Rectangle().fill(Color("Sand")).frame(height: 0.5)
                        HStack(spacing: 0) {
                            ForEach(Array(breakdown.rows.dropFirst().enumerated()), id: \.element.id) { i, row in
                                if i > 0 { Spacer(minLength: 10) }
                                (Text(row.name + " ").font(.system(size: 14)).foregroundStyle(Color("Ink2"))
                                 + Text("\(Int(row.percent.rounded()))%").font(.clausagePercent(15)).foregroundStyle(Color("Ink")))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .brandCard()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(breakdown.rows.map { "\($0.name) \(Int($0.percent.rounded())) percent" }.joined(separator: ", "))
            }
        }
    }
}

// MARK: Usage credits (one read-only row)

struct CreditsCard: View {
    let credits: UsageCredits
    @Environment(\.openURL) private var openURL

    var body: some View {
        BrandSection(title: "Usage credits") {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(credits.stateText).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color("Ink"))
                    if !credits.detailText.isEmpty {
                        Text(credits.detailText).font(.system(size: 13)).foregroundStyle(Color("Ink2"))
                    }
                }
                Spacer(minLength: 8)
                Button {
                    openURL(URL(string: "https://claude.ai/settings/usage")!)
                } label: {
                    HStack(spacing: 3) {
                        Text("Manage")
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color("EmberDeep"))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens claude.ai usage settings")
            }
            .brandCard()
        }
    }
}

/// Sample mode marker at the top of the Usage and Free screens, so sample numbers are never taken for a real account.
struct SampleBanner: View {
    let scenario: SampleData.Scenario
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Sample data").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color("Ink"))
                Text("\(scenario.name). Not a real account.").font(.system(size: 13)).foregroundStyle(Color("Ink2"))
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("Exit", action: onExit)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color("Ink"))
                .padding(.horizontal, 12).frame(minHeight: 32)
                .background(Color("Paper"), in: Capsule())
                .accessibilityLabel("Exit sample mode")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color("Sand2"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
