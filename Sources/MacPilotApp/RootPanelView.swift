import MacPilotCalendar
import MacPilotCore
import MacPilotFan
import MacPilotSystemActions
import SwiftUI

struct RootPanelView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var calendar: CalendarReminderController
    @ObservedObject var fans: FanStore
    @ObservedObject var tools: SystemToolsStore
    @ObservedObject var voice: VoiceStore
    let cleaning: CleaningOverlayController
    let openSettings: () -> Void
    @State private var selectedTab: DashboardTab = .overview

    var body: some View {
        VStack(spacing: 12) {
            header
            Picker("页面", selection: $selectedTab) {
                ForEach(DashboardTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch selectedTab {
                case .overview:
                    OverviewView(store: store, calendar: calendar, fans: fans, tools: tools, cleaning: cleaning)
                case .fans:
                    FansView(store: fans)
                case .tools:
                    ToolsView(calendar: calendar, tools: tools, cleaning: cleaning)
                case .voice:
                    VoiceView(store: voice)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .frame(width: 430, height: 660)
        .background(panelBackground)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.lastErrorDescription == nil ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            Text("MacPilot")
                .font(.headline)
            Spacer()
            Text(Date(), style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("打开设置")
        }
    }

    private var panelBackground: some View {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor), Color.blue.opacity(0.07), Color.purple.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
