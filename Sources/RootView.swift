import SwiftUI
import Photos
import UIKit

struct RootView: View {
    @EnvironmentObject private var library: PhotoLibraryService
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if library.isAuthorized {
                TabView {
                    FilterView(showSettings: $showSettings)
                        .tabItem { Label("浏览", systemImage: "photo.on.rectangle.angled") }
                    DuplicatesView()
                        .tabItem { Label("重复", systemImage: "square.on.square") }
                    SmartView()
                        .tabItem { Label("分类", systemImage: "sparkles") }
                    StorageView()
                        .tabItem { Label("体积", systemImage: "internaldrive") }
                }
                .tint(Theme.accent)
            } else {
                PermissionGate()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("提示", isPresented: errorBinding) {
            Button("好", role: .cancel) {
                library.errorMessage = nil
            }
        } message: {
            Text(library.errorMessage ?? "")
        }
        .task {
            await library.bootstrap()
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { library.errorMessage != nil },
            set: { newValue in
                if !newValue { library.errorMessage = nil }
            }
        )
    }
}

// MARK: - 授权页

struct PermissionGate: View {
    @EnvironmentObject private var library: PhotoLibraryService
    @State private var working = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.14))
                    .frame(width: 104, height: 104)
                Image(systemName: "photo.stack")
                    .font(.system(size: 42, weight: .light))
                    .foregroundColor(Theme.accent)
            }

            Text("需要访问你的相册")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text("相册管家需要读取照片和视频，用来查找重复、按条件筛选、智能分类。\n所有分析都在这台 iPhone 上完成，不会上传任何内容。")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 32)

            Button(working ? "正在请求…" : "允许访问照片") {
                guard !working else { return }
                working = true
                Task {
                    await library.requestPermission()
                    working = false
                }
            }
            .buttonStyle(FillButtonStyle())
            .disabled(working)

            if library.status == .denied || library.status == .restricted {
                Button("前往系统设置中开启") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(GhostButtonStyle())
            }

            Spacer()

            Text("建议选择「完全访问」，否则只能整理你授权的部分照片。")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject private var library: PhotoLibraryService
    @EnvironmentObject private var tags: TagStore
    @Environment(\.dismiss) private var dismiss

    private var photoCount: Int { library.items.filter { $0.isPhoto }.count }
    private var videoCount: Int { library.items.filter { $0.isVideo }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("授权状态", library.accessLevelText)
                    row("照片", "\(photoCount) 项")
                    row("视频", "\(videoCount) 项")
                    row("已统计体积", library.totalBytes > 0 ? Fmt.bytes(library.totalBytes) : "未统计")
                    row("智能标签", "\(tags.count) 项")
                } header: {
                    Text("相册概览")
                }

                Section {
                    if library.status == .limited {
                        Button("选择更多可访问照片") {
                            library.presentLimitedPicker()
                        }
                        .foregroundColor(Theme.accent)
                    }
                    if library.status == .denied {
                        Button("前往系统设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .foregroundColor(Theme.accent)
                    }

                    Button("重新读取相册") {
                        Task { await library.loadLibrary() }
                    }
                    .foregroundColor(Theme.textPrimary)

                    Button {
                        Task { await library.measureSizes(force: true) }
                    } label: {
                        HStack {
                            Text("统计文件体积")
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            if library.isMeasuring {
                                Text("\(Int(library.sizeProgress * 100))%")
                                    .foregroundColor(Theme.accent)
                            }
                        }
                    }
                    .disabled(library.isMeasuring)

                    Button("清除智能分类缓存") {
                        tags.clear()
                    }
                    .foregroundColor(Theme.danger)
                } header: {
                    Text("维护")
                }

                Section {
                    Text("相册管家 1.0 · 本地离线处理")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                    Text("本应用通过系统 PhotoKit 读取相簿，删除操作只是把项目移入「最近删除」，不会立刻抹除数据。所有查重与分类计算都在设备上进行。")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .lineSpacing(4)
                } header: {
                    Text("关于")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                library.refreshStatus()
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
        }
    }
}
