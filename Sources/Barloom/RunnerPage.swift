import BarloomCore
import SwiftUI

struct RunnerPage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var body: some View {
        VStack(spacing: 20) {
            Surface {
                HStack {
                    SectionHeading(title: "Meet your menu bar companion", detail: "Animation follows CPU usage from the shared monitoring engine.")
                    Spacer()
                    Toggle("Enable Runner", isOn: $model.preferences.runnerEnabled).labelsHidden().toggleStyle(.switch)
                }
            }
            Surface {
                VStack(spacing: 24) {
                    RunnerPreview(character: model.preferences.runnerCharacter, cpuUsage: model.snapshot?.cpuUsage,
                                  paused: !model.preferences.runnerEnabled || model.preferences.reduceMotion || systemReduceMotion)
                        .frame(height: 150)
                    HStack(spacing: 24) {
                        VStack(spacing: 5) {
                            Text(MetricFormat.percent(model.snapshot?.cpuUsage)).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("CPU usage").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Divider().frame(height: 35)
                        VStack(spacing: 5) {
                            Text(model.preferences.reduceMotion || systemReduceMotion ? "Still" : String(format: "%.1f fps", AnimationCadence.framesPerSecond(cpuUsage: model.snapshot?.cpuUsage)))
                                .font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("Animation pace").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Text("A gentle stroll at idle. A faster pace when things get busy.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            Surface {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "Pick a character", detail: "Three original animations, drawn natively.")
                    HStack(spacing: 12) {
                        ForEach(RunnerCharacter.allCases) { character in
                            Button { model.preferences.runnerCharacter = character } label: {
                                VStack(spacing: 15) {
                                    Image(nsImage: StatusArtwork.image(for: character, frame: 0)).resizable().scaledToFit().frame(width: 52, height: 40)
                                    Text(character.title).font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(model.preferences.runnerCharacter == character ? AppColors.violet : .primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 23)
                                .background(model.preferences.runnerCharacter == character ? AppColors.violet.opacity(0.08) : .primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.preferences.runnerCharacter == character ? AppColors.violet.opacity(0.5) : .primary.opacity(0.07), lineWidth: 1))
                            }.buttonStyle(.plain)
                            .accessibilityAddTraits(model.preferences.runnerCharacter == character ? .isSelected : [])
                        }
                    }
                    Divider()
                    HStack {
                        SectionHeading(title: "Reduce motion", detail: "Keep a still character in the menu bar. macOS’s setting is also respected.")
                        Spacer()
                        Toggle("Reduce motion", isOn: $model.preferences.reduceMotion).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    Text("Custom animation imports are planned for a later milestone.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct RunnerPreview: View {
    let character: RunnerCharacter
    let cpuUsage: Double?
    let paused: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 8, paused: paused)) { context in
            let pace = AnimationCadence.framesPerSecond(cpuUsage: cpuUsage)
            let frame = paused ? 0 : Int(context.date.timeIntervalSinceReferenceDate * pace) % 8
            ZStack {
                Circle().fill(AppColors.violet.opacity(0.06)).frame(width: 144, height: 144)
                Circle().strokeBorder(AppColors.violet.opacity(0.08), lineWidth: 1).frame(width: 112, height: 112)
                Image(nsImage: StatusArtwork.image(for: character, frame: frame))
                    .resizable().scaledToFit().foregroundStyle(AppColors.violet).frame(width: 82, height: 64)
            }
        }.accessibilityLabel("\(character.title) animation preview")
    }
}
