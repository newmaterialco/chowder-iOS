import ActivityKit
import SwiftUI
import WidgetKit

struct ChowderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChowderActivityAttributes.self) { context in
            lockScreenBanner(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Circle()
                        .fill(context.state.isFinished ? Color.green : Color.blue)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.agentName)
                            .font(.headline)
                        Text(context.state.currentIntent)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.isFinished {
                        Text("Step \(context.state.stepNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let prev = context.state.previousIntent, !context.state.isFinished {
                        HStack(spacing: 6) {
                            Image("tick")
                                .foregroundStyle(.green)
                            Text(prev)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Circle()
                    .fill(context.state.isFinished ? Color.green : Color.blue)
                    .frame(width: 6, height: 6)
            } compactTrailing: {
                if context.state.isFinished {
                    Text("Done")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text(context.state.currentIntent)
                        .font(.caption2)
                        .lineLimit(1)
                        .frame(maxWidth: 64)
                }
            } minimal: {
                Circle()
                    .fill(context.state.isFinished ? Color.green : Color.blue)
                    .frame(width: 6, height: 6)
            }
        }
    }
    
    // MARK: - Lock Screen Banner
    
    @ViewBuilder
    private func lockScreenBanner(context: ActivityViewContext<ChowderActivityAttributes>) -> some View {
        let state = context.state
        
        // Collect unique intents (filter out empty strings and duplicates)
        let intents: [String] = [state.secondPreviousIntent, state.previousIntent]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        
        let isWaiting = intents.isEmpty
        
        @Environment(\.colorScheme) var colorScheme
        
        
        let primaryForeground: Color = Color(red: 47/255, green: 59/255, blue: 84/255)
        let userTaskOpacity: CGFloat = colorScheme == .dark ? 0.24 : 0.12
        
        VStack(alignment: .leading, spacing: 4) {
            // Header: task + cost badge
            HStack(spacing: 10) {
                
                HStack {
                    agentAvatar()
                        .frame(width: 21, height: 21)
                        .clipShape(.circle)
                        .overlay {
                            Circle()
                                .stroke(primaryForeground.opacity(0.12))
                        }
                    
                    Group {
                        if intents.isEmpty || state.isFinished {
                            Text(context.attributes.agentName)
                        } else {
                            Text(state.subject ?? "Figuring it out")
                                .id(state.subject)
                        }
                    }
                    .font(.callout.bold())
                    .opacity(0.72)
                    .lineLimit(1)
                    .transition(.blurReplace)
                }
                
                
                
                Spacer()
                
                
                if let cost = state.costTotal {
                    let alert = !cost.contains("$0")
                    
                    Text(cost)
                        .font(.subheadline)
                        .fontWeight(.regular)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .overlay {
                            Capsule()
                                .stroke(primaryForeground.opacity(alert ? 0.06 : 0.12))
                        }
                        .background(primaryForeground.opacity(alert ? 0.12 : 0), in: .capsule)
                        .monospacedDigit()
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.fill")
                            .resizable()
                            .foregroundStyle(.green)
                            .frame(width: 5, height: 5)
                            .symbolEffect(.pulse)
                        
                        Text("OpenClaw")
                            .opacity(0.48)
                    }
                    .transition(.blurReplace)
                }
            }
            .font(.subheadline.bold())
            .frame(height: 28)
            .padding(.horizontal, 6)
            .foregroundStyle(primaryForeground)
            
            // Stacked cards for previous intents - keyed by the intent text itself
            ZStack {
                if state.intentEndDate != nil {
                    VStack(alignment: .center, spacing: 8) {
                        Image("tick")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Color.white)
                            .frame(width: 28)
                            .background(Color.green, in: .circle)
                            .compositingGroup()
                        VStack (spacing: 2) {
                            Text(state.subject ?? "Task complete")
                                .font(.subheadline.bold())
                                .foregroundStyle(primaryForeground)
                            Text("See more details…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
                } else {
                    ZStack {
                        if intents.isEmpty {
                            Text(context.attributes.userTask)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.blue)
                                .padding(12)
                                .frame(minWidth: 52)
                                .background(
                                    Color.blue.opacity(userTaskOpacity),
                                    in: .rect(cornerRadius: 16, style: .continuous)
                                )
                                .overlay(alignment: .bottomTrailing, content: {
                                    Image(.messageBubble)
                                        .renderingMode(.template)
                                        .offset(y: 10)
                                        .foregroundStyle(.blue.opacity(userTaskOpacity))
                                })
                                .padding(.leading, 48)
                                .padding(.trailing, 8)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .transition(.blurReplace)
                        }
                        
                        
                        ForEach(intents, id: \.self) { intent in
                            let isBehind = intent != state.previousIntent
                            
                            IntentCard(text: intent, isBehind: isBehind)
                        }
                    }
                    .compositingGroup()
                    .transition(.blurReplace)
                }
            }
            .frame(height: 80)
            .padding(.bottom, 8)
            .frame(maxHeight: .infinity)
            .zIndex(10)
            
            // Footer: current intent + timer
            HStack(spacing: 6) {
                if state.isFinished {
                    Text("^[\(state.stepNumber) step](inflect: true)")
                        .transition(.blurReplace)
                        .padding(.leading, 8)
                } else {
                    HStack(spacing: 2) {
                        Text(Image(systemName: state.currentIntentIcon ?? "arrow.turn.down.right"))
                            .frame(width: 24, height: 18)
                        
                        Text(isWaiting ? "Thinking…" : state.currentIntent)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    }
                    .id(state.currentIntent)
                    .transition(.blurReplace)
                }
                
                Spacer()
                
                Group {
                    if let endDate = state.intentEndDate {
                        let interval = Duration.seconds(endDate.timeIntervalSince(state.intentStartDate))
                        Text("Finished in \(interval.formatted(.time(pattern: .minuteSecond)))")
                    } else if !isWaiting {
                        Text("00:00")
                            .opacity(0)
                            .overlay(alignment: .trailing) {
                                Text(state.intentStartDate, style: .timer)
                                    .contentTransition(.numericText(countsDown: false))
                                    .opacity(0.5)
                            }
                    }
                }
                .font(.footnote.bold())
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .layoutPriority(1)
            }
            .foregroundStyle(primaryForeground)
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .font(.footnote.bold())
            .opacity(isWaiting || state.isFinished ? 0.36 : 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(height: 160)
        .background(Color.white.opacity(isWaiting || state.isFinished ? 1 : 0.75))
        .activityBackgroundTint(.clear)
    }
    
    @ViewBuilder
    private func agentAvatar() -> some View {
        if false, let uiImage = SharedStorage.loadAvatarImage() {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Image(.oddjob)
                .resizable()
                .scaledToFit()
        }
    }
}

struct IntentCard: View {
    let text: String
    let isBehind: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image("tick")
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.black.opacity(0.5))
                .frame(width: 21)
                .background(
                    Circle()
                        .foregroundStyle(.black.opacity(0.12))
                )
            
            Text(text)
                .font(.callout)
                .foregroundStyle(.black)
                .frame(height: 60)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 60)
        .background(Color.white, in: .rect(cornerRadius: isBehind ? 10 : 16, style: .continuous))
        .scaleEffect(isBehind ? 0.9 : 1)
        .offset(y: isBehind ? 10 : 0)
        .opacity(isBehind ? 0.72 : 1)
        .zIndex(isBehind ? 0 : 1)
        .transition(.asymmetric(
            insertion: .offset(y: 120),
            removal: .opacity
        ))
    }
}

// MARK: - Previews

#Preview("Lock Screen - In Progress", as: .content, using: ChowderActivityAttributes.preview) {
    ChowderLiveActivity()
} contentStates: {
    ChowderActivityAttributes.ContentState.step1
    ChowderActivityAttributes.ContentState.step2
    ChowderActivityAttributes.ContentState.step3
    ChowderActivityAttributes.ContentState.step4
    ChowderActivityAttributes.ContentState.step5
    ChowderActivityAttributes.ContentState.step6
    ChowderActivityAttributes.ContentState.finished
}

#Preview("Lock Screen - Finished", as: .content, using: ChowderActivityAttributes.preview) {
    ChowderLiveActivity()
} contentStates: {
    ChowderActivityAttributes.ContentState.finished
}
