import ActivityKit
import SwiftUI
import WidgetKit

private let chatURL = URL(string: "wintermute-island://chat")
private typealias Context = ActivityViewContext<IslandAttributes>

private func symbol(_ context: Context) -> String {
  switch context.state.phase {
  case "reply": return "envelope.fill"
  case "ended": return "checkmark"
  default: return context.isStale ? "arrow.clockwise" : "ellipsis"
  }
}

private func status(_ context: Context) -> String {
  switch context.state.phase {
  case "reply": return "收到新回复"
  case "ended": return "处理已结束"
  default: return context.isStale ? "打开对话同步进度" : "正在回复"
  }
}

private struct CatHead: View {
  var body: some View {
    Image("island-head").renderingMode(.original).resizable().scaledToFit()
      .accessibilityLabel("Wintermute")
  }
}

private struct TodaySummary: View {
  let context: Context
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("今日通知与安排").font(.caption.bold())
      if let end = context.state.dayEnd, end > Date(), !context.state.lines.isEmpty {
        ForEach(context.state.lines, id: \.self) { Text($0).font(.caption).lineLimit(1).privacySensitive() }
      } else {
        Text("打开应用查看今天的内容").font(.caption)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

@main
struct WintermuteIsland: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: IslandAttributes.self) { context in
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          CatHead().frame(width: 28, height: 24)
          Text(status(context)).font(.headline)
        }
        TodaySummary(context: context)
      }
      .padding().widgetURL(chatURL)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) { TodaySummary(context: context) }
      } compactLeading: {
        CatHead().frame(width: 23, height: 19)
      } compactTrailing: {
        Image(systemName: symbol(context)).accessibilityLabel(status(context))
      } minimal: {
        CatHead()
      }
      .widgetURL(chatURL)
    }
  }
}
