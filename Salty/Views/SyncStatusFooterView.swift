// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

//
//  SyncStatusFooterView.swift
//  Salty
//
//  Photos-style sync status row for the bottom of the iOS sidebar and Shopping Lists lists: a quiet
//  "Last synced …" line that becomes a progress line while syncing, and taps as Sync Now. Hidden
//  entirely unless server sync is enabled, the same way Photos' status line only exists with iCloud
//  Photos on. Pairs with pull-to-refresh on the same lists; both run through ManualSyncRunner.
//

import SwiftUI

struct SyncStatusFooterView: View {
    @State private var syncService = SaltySyncService.shared
    @AppStorage("serverUse") private var serverUse = false

    var body: some View {
        if serverUse {
            Button {
                Task { await ManualSyncRunner.shared.sync() }
            } label: {
                HStack(spacing: 6) {
                    if syncService.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LastSyncedLabel(date: syncService.lastSyncDate)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(syncService.isSyncing)
            .accessibilityLabel("Sync Now")
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }
}
