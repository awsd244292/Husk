// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UniformTypeIdentifiers

/// The JIT walkthrough: pick a way in, follow its numbered steps, end with JIT on.
///
/// Three ways in. Pairing on this iPhone (iOS 27) and a pairing file made on a
/// computer both lead to Built-in StikJIT and share the last two steps,
/// LocalDevVPN and enabling. StikDebug has its own short page. Presented from
/// onboarding, Settings › JIT, and whenever Start finds JIT not set up.
struct JITSetupFlow: View {
    enum Step: Hashable { case pairOnDevice, importFile, connect, enable, stikDebug, trollStore, jailbreak }

    @ObservedObject private var jit = JITCoordinator.shared
    @ObservedObject private var pairing = OnDevicePairing.shared
    @State private var path: [Step] = []
    @State private var importing = false
    @Environment(\.dismiss) private var dismiss

    private var device: String { OnDevicePairing.deviceKind }

    var body: some View {
        NavigationStack(path: $path) {
            choose
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .pairOnDevice: pairOnDevice
                    case .importFile: importFile
                    case .connect: connect
                    case .enable: enable
                    case .stikDebug: stikDebug
                    case .trollStore: trollStore
                    case .jailbreak: jailbreak
                    }
                }
        }
        .tint(Theme.accent)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.propertyList, .data]) { result in
            switch result {
            case .success(let url): jit.importPairingFile(url)
            case .failure(let failure):
                HuskLog.log("jit", "pairing import failed: \(failure.localizedDescription)")
            }
        }
        .onAppear {
            jit.refreshPairingStatus()
            pairing.reset()
            // A failed enable from the Library lands on the step that can fix it.
            if jit.error != nil, jit.hasPairing, jit.resolvedMethod == .builtIn {
                path = [.enable]
            }
            HuskLog.log("ui", "JIT walkthrough opened")
        }
        // Swiping the sheet away, or a copy shown from onboarding, must not
        // leave a request to show it again behind.
        .onDisappear { jit.showSetup = false }
    }

    private func close() {
        jit.showSetup = false
        dismiss()
    }

    // MARK: Choose

    private var choose: some View {
        page(symbol: "bolt.fill", title: "开启 JIT",
             subtitle: "Android 需要可写入并可执行的内存，在 iOS 上只有已附加的调试器才能授予。"
                     + "请选择你的 \(device) 获取调试器的方式。") {
            VStack(spacing: 10) {
                let builtIn = HuskBuiltInJIT.unavailableReason
                way("在这台 \(device) 上配对", symbol: "iphone.radiowaves.left.and.right",
                    detail: builtIn ?? (!OnDevicePairing.isSupported ? "需要 iOS 27 或更高版本。"
                        : jit.pairingSource == .onDevice ? "已在这台 \(device) 上配对。"
                        : "无需电脑。在“设置”中一分钟即可完成配对。"),
                    done: jit.pairingSource == .onDevice,
                    enabled: builtIn == nil && OnDevicePairing.isSupported) { path.append(.pairOnDevice) }
                way("使用配对文件", symbol: "doc.badge.plus",
                    detail: builtIn ?? (jit.pairingSource == .imported ? "配对文件已导入。"
                        : "导入在电脑上生成的配对文件。"),
                    done: jit.pairingSource == .imported,
                    enabled: builtIn == nil) { path.append(.importFile) }
                way("使用 StikDebug", symbol: "ant",
                    detail: JITBootstrap.isStikDebugInstalled ? "StikDebug 已安装。"
                        : "通过 StikDebug 应用开启 JIT。",
                    done: jit.method == .stikDebug) { path.append(.stikDebug) }
                way("使用 TrollStore", symbol: "sparkles",
                    detail: JITBootstrap.isTrollStoreInstalled ? "TrollStore 已安装。"
                        : "适用于通过 TrollStore 安装的 Husk。",
                    done: jit.method == .trollStore) { path.append(.trollStore) }
                way("使用越狱", symbol: "lock.open",
                    detail: JITBootstrap.debuggedAtLaunch ? "Husk 打开时 JIT 已开启。"
                        : JITBootstrap.isJailbroken ? "检测到越狱。请打开“在应用中允许 JIT”。"
                        : "只需一个设置，Dopamine 即可为所有应用提供 JIT。",
                    done: jit.method == .jailbreak || JITBootstrap.debuggedAtLaunch) { path.append(.jailbreak) }
            }
            if jit.hasPairing && HuskBuiltInJIT.isAvailable {
                Button { path.append(.connect) } label: {
                    Label("继续使用当前配对", systemImage: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.top, 4)
            }
        } actions: {
            Button("暂不") { close() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textDim)
        }
    }

    private func way(_ title: String, symbol: String, detail: String, done: Bool,
                     enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(detail).font(.system(size: 13)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: done ? 18 : 13, weight: .semibold))
                    .foregroundStyle(done ? .green : Theme.textDim.opacity(0.7))
            }
            .padding(14)
            .contentShape(Rectangle())
            .huskCard()
        }
        .buttonStyle(CardButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    // MARK: Pair on this device

    private var pairedOnDevice: Bool {
        if case .paired = pairing.phase { return true }
        return false
    }

    private var pairOnDevice: some View {
        page(symbol: "iphone.radiowaves.left.and.right", title: "在这台 \(device) 上配对",
             subtitle: "Husk 会在你的 Wi-Fi 中扮作一台电脑，你的 \(device) 像连接 Mac 一样与它配对。") {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "打开 Wi-Fi，轻点下方的“**开始配对**”，并允许本地网络访问。",
                      done: pairing.phase != .idle)
                point(2, "打开“**设置 › 隐私与安全性 › 开发者模式**”，滚动到底部并轻点"
                       + "“**与 \(OnDevicePairing.hostName) 配对**”。",
                      done: pairing.isShowingPin || pairedOnDevice)
                point(3, "输入 Husk 显示的代码。代码也会出现在横幅和通知中，"
                       + "无需切换回来查看。",
                      done: pairedOnDevice)
                point(4, "返回 Husk。", done: pairedOnDevice)
            }
            .padding(16).huskCard()
            pairingStatus
        } actions: {
            switch pairing.phase {
            case .idle, .failed:
                Button { pairing.start() } label: {
                    Label("开始配对", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(PrimaryButtonStyle())
            case .waiting, .pin:
                Button("取消配对", role: .cancel) { pairing.cancel() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            case .paired:
                Button("继续") { path.append(.connect) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    @ViewBuilder private var pairingStatus: some View {
        switch pairing.phase {
        case .idle:
            EmptyView()
        case .waiting:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.accent)
                    Text("正在等待你的 \(device)…").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                Button("打开设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.system(size: 14, weight: .semibold))
                if pairing.backgroundLimited {
                    Text("此安装版本在后台只能等待约 30 秒，请立即前往“设置”。")
                        .font(.system(size: 13)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).huskCard()
        case .pin(let pin):
            VStack(spacing: 8) {
                Text("在这台 \(device) 上输入此代码").font(.system(size: 14))
                    .foregroundStyle(Theme.textDim)
                Text(pin).font(.system(size: 40, weight: .bold, design: .monospaced)).tracking(6)
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .accessibilityLabel("配对代码 \(pin.map(String.init).joined(separator: " "))")
            }
            .frame(maxWidth: .infinity)
            .padding(18).huskCard(high: true)
        case .paired(let name):
            outcome("已与 \(name) 配对", ok: true)
        case .failed(let message):
            outcome(message, ok: false)
        }
    }

    // MARK: Import a pairing file

    private var importFile: some View {
        page(symbol: "doc.badge.plus", title: "使用配对文件",
             subtitle: "在电脑上生成的配对文件，可让 Husk 以同样的方式与这台 \(device) 通信。") {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "在电脑上，按照 [StikDebug 配对文件指南](https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md) "
                       + "为这台 \(device) 生成配对文件。",
                      done: jit.pairingSource == .imported)
                point(2, "将它存储到“文件”，或通过隔空投送发送到这台 \(device)。",
                      done: jit.pairingSource == .imported)
                point(3, "轻点“**选取配对文件**”并选中它。", done: jit.pairingSource == .imported)
            }
            .padding(16).huskCard()
            Label("配对文件保存在 Husk 的“文稿”文件夹中，且只会发送给 Husk 自身的辅助进程。",
                  systemImage: "lock.fill")
                .font(.system(size: 13)).foregroundStyle(Theme.textDim)
            if let error = jit.error { outcome(error, ok: false) }
        } actions: {
            if jit.pairingSource == .imported {
                Button("继续") { path.append(.connect) }.buttonStyle(PrimaryButtonStyle())
                Button("选取其他文件") { importing = true }
                    .font(.system(size: 15, weight: .medium))
            } else {
                Button { importing = true } label: { Label("选取配对文件", systemImage: "folder") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: LocalDevVPN

    private var connect: some View {
        page(symbol: "network.badge.shield.half.filled", title: "连接 LocalDevVPN",
             subtitle: "Husk 的辅助进程通过本地 VPN 连接这台 \(device) 的调试服务。"
                     + "不会有任何数据离开你的 \(device)。") {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "从 App Store 安装 [LocalDevVPN](\(LocalDevVPN.appStore.absoluteString))。",
                      done: LocalDevVPN.isInstalled)
                point(2, "轻点“**连接 LocalDevVPN**”。它会开启 VPN 并直接返回 Husk。")
                point(3, "开启 JIT 时请保持其处于连接状态。")
            }
            .padding(16).huskCard()
        } actions: {
            Button(LocalDevVPN.actionTitle) { LocalDevVPN.open() }
                .buttonStyle(PrimaryButtonStyle())
            Button("已连接") { path.append(.enable) }
                .font(.system(size: 15, weight: .medium))
        }
    }

    // MARK: Enable

    private var attached: Bool { jit.attachGeneration > 0 || JITBootstrap.debuggedFlag }

    private var enable: some View {
        page(symbol: "bolt.badge.checkmark", title: "开启 JIT",
             subtitle: "首次检查会下载并装载 Apple 的开发者磁盘映像，"
                     + "可能需要一分钟。") {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "轻点“**检查设置**”。Husk 会检查 LocalDevVPN 并准备开发者磁盘映像。",
                      done: jit.prepared || attached)
                point(2, "轻点“**开启 JIT**”。Husk 的辅助进程附加后，Android 便可启动。", done: attached)
            }
            .padding(16).huskCard()

            if jit.busy {
                HStack(spacing: 11) {
                    ProgressView().tint(Theme.accent)
                    Text(jit.status ?? "正在处理…").font(.system(size: 14)).foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                }
                .padding(16).huskCard(high: true)
            } else if attached {
                outcome("JIT 已开启。Android 可以启动了。", ok: true)
            } else if let error = jit.error {
                VStack(alignment: .leading, spacing: 10) {
                    outcome(error, ok: false)
                    if jit.connectionProblem == .pairing {
                        Button(OnDevicePairing.isSupported ? "重新配对" : "导入新的配对文件") {
                            path = [OnDevicePairing.isSupported ? .pairOnDevice : .importFile]
                        }
                        .font(.system(size: 14, weight: .semibold))
                    }
                    if jit.connectionProblem != nil {
                        Button(LocalDevVPN.actionTitle) { LocalDevVPN.open() }
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            } else if let status = jit.status {
                outcome(status, ok: true)
            }

            if !attached {
                Button("重置开发者磁盘映像", role: .destructive) { jit.resetDDI() }
                    .font(.system(size: 13, weight: .medium))
                    .disabled(jit.busy)
                    .padding(.top, 4)
            }
        } actions: {
            if attached {
                Button("完成") { close() }.buttonStyle(PrimaryButtonStyle())
            } else if jit.prepared {
                Button { jit.enableBuiltIn() } label: { Label("开启 JIT", systemImage: "bolt.fill") }
                    .buttonStyle(PrimaryButtonStyle(enabled: !jit.busy))
                    .disabled(jit.busy)
            } else {
                Button("检查设置") { jit.prepareBuiltIn() }
                    .buttonStyle(PrimaryButtonStyle(enabled: !jit.busy))
                    .disabled(jit.busy)
            }
        }
    }

    // MARK: StikDebug

    private var stikDebug: some View {
        page(symbol: "ant", title: "使用 StikDebug",
             subtitle: "StikDebug 是一个单独的应用，会附加到 Husk。Husk 会将 JIT 脚本一并发送给它，"
                     + "因此无需在 StikDebug 中为 Husk 做任何配置。") {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "安装 [StikDebug](https://github.com/StikDebug/StikDebug/releases/latest)。",
                      done: JITBootstrap.isStikDebugInstalled)
                point(2, "将这台 \(device) 的配对文件导入 StikDebug。")
                point(3, "安装并连接 [LocalDevVPN](\(LocalDevVPN.appStore.absoluteString))。")
                point(4, "Android 每次启动时，Husk 都会打开 StikDebug，它会附加调试器后返回。")
            }
            .padding(16).huskCard()
        } actions: {
            Button("使用 StikDebug") {
                jit.method = .stikDebug
                HuskLog.log("ui", "JIT method set to StikDebug")
                close()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: TrollStore

    private var trollStore: some View {
        page(symbol: "sparkles", title: "使用 TrollStore",
             subtitle: "TrollStore 可以为它安装的应用开启 JIT，"
                     + "无需配对文件、VPN 或电脑。") {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "在 TrollStore 支持的 iOS 版本上，通过 TrollStore 安装 Husk.ipa。它保留了 TrollStore "
                       + "留存的签名权限，因此同一个文件在 TrollStore 和侧载工具中都能使用。",
                      done: JITBootstrap.isInstalledWithTrollStore)
                point(2, "在 TrollStore 的设置中打开 URL Scheme。否则 TrollStore 会忽略 enable-jit 请求。",
                      done: JITBootstrap.isTrollStoreInstalled)
                point(3, "Android 或游戏每次启动时，Husk 都会请求 TrollStore 开启 JIT。TrollStore 会打开 Husk，"
                       + "短暂附加调试器后释放，使 Husk 可以运行自己写入的代码。")
            }
            .padding(16).huskCard()
            if !JITBootstrap.isTrollStoreInstalled {
                Label("这台 \(device) 上未找到 TrollStore。只有在 TrollStore 已安装且 Husk 是通过它安装时，"
                    + "才能使用此方式。", systemImage: "info.circle")
                    .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            Button("使用 TrollStore") {
                jit.method = .trollStore
                HuskLog.log("ui", "JIT method set to TrollStore")
                close()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: Jailbreak

    private var jailbreak: some View {
        page(symbol: "lock.open", title: "使用越狱",
             subtitle: "在使用 Dopamine 越狱的设备上，JIT 只是一项设置：越狱会把每个打开的应用标记为已调试，"
                     + "而已调试的应用可以运行自己写入的代码。Husk 无需其他任何操作。") {
            VStack(alignment: .leading, spacing: 14) {
                point(1, "打开 Dopamine 并进入其设置。", done: JITBootstrap.isJailbroken)
                point(2, "打开“在应用中允许 JIT”。")
                point(3, "彻底关闭 Husk 后重新打开。此设置会在应用启动时生效。",
                      done: JITBootstrap.debuggedAtLaunch)
            }
            .padding(16).huskCard()
            if JITBootstrap.debuggedAtLaunch {
                Label("Husk 打开时已被标记为已调试，因此 JIT 已开启。", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(.green)
            } else if !JITBootstrap.isJailbroken {
                Label("这台 \(device) 上未检测到越狱。", systemImage: "info.circle")
                    .font(.system(size: 13)).foregroundStyle(Theme.textDim)
            }
        } actions: {
            Button("使用越狱") {
                jit.method = .jailbreak
                HuskLog.log("ui", "JIT method set to jailbreak")
                close()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: Pieces

    private func page<Content: View, Actions: View>(
        symbol: String, title: String, subtitle: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions) -> some View {
        ZStack {
            Theme.backdrop
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 56, height: 56)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text(title).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    content()
                }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) { actions() }
                .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 16)
                .background(Theme.backdrop)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("关闭") { close() }
            }
        }
    }

    private func point(_ number: Int, _ text: String, done: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green.opacity(0.18) : Theme.accentSoft)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.green)
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 26, height: 26)
            Text(.init(text))
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func outcome(_ text: String, ok: Bool) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(ok ? .green : .red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).huskCard()
    }
}
